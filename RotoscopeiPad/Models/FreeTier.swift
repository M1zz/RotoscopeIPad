import Foundation
import StoreKit
import LeeoKit

/// What a free install can do. The limits themselves live in one place —
/// `RotoscopeiPadSpec.monetization` — this file names the keys, the free
/// guide sets, and decides who already counts as a paying user.
enum FreeTier {
    /// The one thing we sell: a non-consumable "평생 이용권" (Family Sharing on).
    static let lifetimeProductID = "com.leeo.RotoscopeiPad.lifetime"
    /// A consumable a grown-up buys to give the lifetime pass to someone
    /// else (`RotoscopeiPadSpec.monetization.gift`). Never sold as Pro itself.
    static let giftProductID = "com.leeo.RotoscopeiPad.gift.pro"

    // Gate keys (see RotoscopeiPadSpec.monetization).
    static let projectKey = "project"            // saved works on the home grid
    static let blankPageKey = "blankPage"        // pages in one blank flipbook
    static let videoImportKey = "videoImport"    // videos ever brought in
    static let recordSecondsKey = "recordSeconds"
    static let premiumPresetKey = "premiumPreset"

    /// Guide sets anyone can trace. The rest show a lock.
    static let freePresetIDs: Set<String> = ["01_ball", "02_bunny", "05_flower"]

    static func isFree(_ preset: GuidePreset) -> Bool {
        freePresetIDs.contains(preset.id)
    }

    /// Free recording length; nil means unlimited.
    static func recordingLimit(hasPro: Bool) -> TimeInterval? {
        guard !hasPro, let seconds = RotoscopeiPadSpec.gate.freeLimits[recordSecondsKey] else {
            return nil
        }
        return TimeInterval(seconds)
    }

    // MARK: - Video import quota
    // Counted for the lifetime of the install, so deleting a video project
    // and importing another doesn't reset it.

    private static let videoImportsDefaultsKey = "freeTier.videoImports"

    static var videoImportsUsed: Int {
        UserDefaults.standard.integer(forKey: videoImportsDefaultsKey)
    }

    static func recordVideoImport() {
        UserDefaults.standard.set(videoImportsUsed + 1, forKey: videoImportsDefaultsKey)
    }

    // MARK: - Existing users keep everything
    // Everyone who used 팔랑북 while it was free keeps the full app.

    /// Highest build number that shipped while the app was free.
    /// `AppTransaction.originalAppVersion` is the CFBundleVersion of the
    /// first download, so anything at or below this was a free install.
    private static let lastFreeBuild = 2

    private static let legacyCheckedKey = "freeTier.legacyChecked"
    private static let legacyUserKey = "freeTier.legacyUser"

    /// Runs once per install, before anything is created: projects already on
    /// disk at the first launch of the freemium build mean a free-era user.
    /// This also covers offline launches, where AppTransaction can't answer.
    @MainActor
    static func markLegacyUserIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyCheckedKey) else { return }
        defaults.set(true, forKey: legacyCheckedKey)
        if !RotoProject.listProjects().isEmpty {
            defaults.set(true, forKey: legacyUserKey)
        }
    }

    /// LeeoStore's grandfather check: asked once per launch while no purchase
    /// is found; a true answer is cached by the store.
    @MainActor
    static func isLegacyUser() async -> Bool {
        if UserDefaults.standard.bool(forKey: legacyUserKey) { return true }
        guard case .verified(let transaction)? = try? await AppTransaction.shared,
              // Sandbox and Xcode always report "1.0" — only trust the App Store.
              transaction.environment == .production,
              let firstBuild = Int(transaction.originalAppVersion) else {
            return false
        }
        return firstBuild <= lastFreeBuild
    }
}

/// Why the unlock sheet came up — picks the icon and the line the parent reads.
enum LockReason: String, Identifiable {
    case projects, presets, video, pages, recording, general

    var id: String { rawValue }

    /// Shown big to the kid before the parent gate (no words needed).
    var icon: String {
        switch self {
        case .projects:  return "square.grid.2x2.fill"
        case .presets:   return "pencil.tip.crop.circle.badge.plus"
        case .video:     return "video.fill"
        case .pages:     return "book.pages.fill"
        case .recording: return "mic.fill"
        case .general:   return "star.fill"
        }
    }

    /// The parent-facing reason on the purchase screen.
    var message: String {
        let limits = RotoscopeiPadSpec.gate.freeLimits
        switch self {
        case .projects:
            return String(localized: "무료로는 작품을 \(limits[FreeTier.projectKey] ?? 0)개까지 보관할 수 있어요.")
        case .presets:
            return String(localized: "따라 그리기 \(FreeTier.freePresetIDs.count)세트는 무료, 나머지는 이용권으로 열려요.")
        case .video:
            return String(localized: "무료로는 동영상을 \(limits[FreeTier.videoImportKey] ?? 0)번 불러올 수 있어요.")
        case .pages:
            return String(localized: "무료로는 빈 종이 플립북을 \(limits[FreeTier.blankPageKey] ?? 0)장까지 그릴 수 있어요.")
        case .recording:
            return String(localized: "무료로는 목소리를 \(limits[FreeTier.recordSecondsKey] ?? 0)초까지 녹음할 수 있어요.")
        case .general:
            return String(localized: "한 번 결제로 팔랑북의 모든 기능을 계속 쓸 수 있어요.")
        }
    }
}
