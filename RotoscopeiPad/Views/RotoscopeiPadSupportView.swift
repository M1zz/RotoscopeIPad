import SwiftUI
import LeeoKit

struct RotoscopeiPadSupportView: View {
    @EnvironmentObject private var store: LeeoStore
    @State private var showUnlock = false
    /// Kids can reach the gear, so feedback, reviews and web links wait
    /// behind the same grown-up check as the purchase screen.
    @State private var parentVerified = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if parentVerified {
            settings
        } else {
            ParentGateView(icon: "gearshape.fill") {
                withAnimation { parentVerified = true }
            }
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .padding(20)
                }
                .accessibilityLabel(Text("닫기"))
            }
        }
    }

    /// Opens the parent's own mail app, addressed to the developer, with the
    /// app name and version in the subject so the reply can find the build.
    private static var mailURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let subject = "\(RotoscopeiPadSpec.displayName) \(version)"
        let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(RotoscopeiPadSpec.developerEmail)?subject=\(encoded)")
    }

    private var settings: some View {
        NavigationStack {
            List {
                Section {
                    if store.hasPro {
                        Label("모든 기능이 열려 있어요", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button { showUnlock = true } label: {
                            Label("평생 이용권", systemImage: "star.fill")
                        }
                    }
                } header: { Text("이용권") }
                if let gift = store.gift {
                    GiftRows(gift: gift, hasPro: store.hasPro)
                }
                Section {
                    LeeoSupportSection<RotoscopeiPadSpec>()
                    NavigationLink(LeeoRoadmapText.entry) { RoadmapScreen() }
                    if let mail = Self.mailURL {
                        Link(destination: mail) {
                            Label("메일로 문의하기", systemImage: "envelope")
                        }
                    }
                    // Only the handle is a proper noun; the label is translated.
                    Link(destination: URL(string: "https://instagram.com/lee25_ios")!) {
                        Label("인스타그램 DM (@lee25_ios)", systemImage: "paperplane")
                    }
                } header: { Text("지원") }
            }
            .navigationTitle("설정")
            .sheet(isPresented: $showUnlock) {
                UnlockSheet(reason: .general)
            }
            // "Enjoying Palang Book?" asks for a store review, so it's only
            // ever put to the grown-up who just passed the check.
            .leeoSatisfactionCheck(RotoscopeiPadSpec.self)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

/// "Gift Pro" and "Enter a gift code", right under the pass section.
///
/// The sender buys a consumable gift; the receiver gets the lifetime pass
/// (`RotoscopeiPadSpec.monetization.gift`). Row titles and the screens
/// themselves come from LeeoKit (`LeeoGiftText`), already in every language.
/// ⚠️ Rows only appear once the gift product loads from the App Store, so a
///    build that ships before the product exists shows nothing dead. Anyone
///    who already paid for, sent or redeemed a gift still sees them, so they
///    can find their code or reach support on a day the product won't load.
/// ⚠️ `LeeoGiftStore` is observed on its own: the product arrives after
///    launch and `LeeoStore` doesn't republish that change.
private struct GiftRows: View {
    @ObservedObject var gift: LeeoGiftStore
    let hasPro: Bool
    @State private var showSupport = false

    var body: some View {
        if gift.isAvailable || gift.pendingCount > 0 || !gift.sentGifts.isEmpty || gift.redeemed != nil {
            Section {
                NavigationLink {
                    // If a gift gets stuck, the bug report carries the payment and code.
                    LeeoGiftView<RotoscopeiPadSpec>(gift: gift, showsRedeemLink: false,
                                                    onContactSupport: { showSupport = true })
                } label: {
                    Label(LeeoGiftText.sendEntry, systemImage: "gift.fill")
                }
                // A Pro user has nothing to redeem; keep the row only to revisit a gift they got.
                if !hasPro || gift.redeemed != nil {
                    NavigationLink {
                        LeeoGiftRedeemView<RotoscopeiPadSpec>(gift: gift,
                                                              onContactSupport: { showSupport = true })
                    } label: {
                        Label(LeeoGiftText.redeemEntry, systemImage: "giftcard")
                    }
                }
            }
            .sheet(isPresented: $showSupport) {
                NavigationStack {
                    LeeoFeedbackView<RotoscopeiPadSpec>(initialType: .bug, extraInfo: gift.supportLines,
                                                        initialCategory: .purchase)
                }
            }
        }
    }
}
