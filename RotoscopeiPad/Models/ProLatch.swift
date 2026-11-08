import Foundation
import Security
import StoreKit

/// Once a family has the lifetime pass, it stays on.
///
/// `LeeoStore` asks `Transaction.currentEntitlements` on every launch, and that
/// list can come back empty for reasons that have nothing to do with the
/// purchase (offline, a fresh iCloud sign-in, Family Sharing still syncing).
/// The latch remembers the pass in the Keychain — which also survives a
/// reinstall — and lets go only when `Transaction.all` shows the purchase
/// was refunded.
enum ProLatch {
    /// What one look at the lifetime pass's transactions says.
    enum Evidence: Equatable {
        case owned      // a live transaction
        case refunded   // transactions exist, every one revoked
        case unknown    // nothing seen — offline, or never bought
    }

    /// Revocation dates of every verified lifetime transaction → evidence.
    static func evidence(revocationDates: [Date?]) -> Evidence {
        if revocationDates.isEmpty { return .unknown }
        return revocationDates.contains { $0 == nil } ? .owned : .refunded
    }

    /// The rule: only a refund lowers the latch; silence never does.
    static func decide(latched: Bool, evidence: Evidence) -> Bool {
        switch evidence {
        case .owned:    return true
        case .refunded: return false
        case .unknown:  return latched
        }
    }

    // MARK: - State

    /// Read once per launch; `LeeoStore`'s `unlockOverride` reads this.
    @MainActor static private(set) var isLatched = Keychain.read()

    /// Looks at the pass's transactions and moves the latch.
    /// - Returns: true when the latch changed (the caller redraws).
    @MainActor @discardableResult
    static func sync() async -> Bool {
        var revocations: [Date?] = []
        for await result in Transaction.all {
            guard case .verified(let tx) = result,
                  tx.productID == FreeTier.lifetimeProductID else { continue }
            revocations.append(tx.revocationDate)
        }
        let latched = decide(latched: isLatched, evidence: evidence(revocationDates: revocations))
        guard latched != isLatched else { return false }
        isLatched = latched
        Keychain.write(latched)
        return true
    }

    // MARK: - Keychain

    private enum Keychain {
        private static let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.leeo.RotoscopeiPad.pro",
            kSecAttrAccount as String: FreeTier.lifetimeProductID
        ]

        static func read() -> Bool {
            var q = query
            q[kSecReturnData as String] = true
            var out: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
                  let data = out as? Data else { return false }
            return data.first == 1
        }

        static func write(_ on: Bool) {
            SecItemDelete(query as CFDictionary)
            guard on else { return }
            var q = query
            q[kSecValueData as String] = Data([1])
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}
