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
                if let tipJar = store.tipJar {
                    TipRows(tipJar: tipJar, hasPro: store.hasPro)
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

// MARK: - 개발자 응원 (팁)

/// 팔랑북이 그 집에 준 것: 끝까지 만들어 사진에 담은 플립북 수.
/// 내보내기가 끝날 때마다 늘어나는 `LeeoEngagement` 의 의미 있는 행동 수가 바로 그 수다 (ContentView.runExport).
enum PalangTipMoments {
    /// 큰 것부터.
    static let flipbooks = [50, 20, 5]

    static func reached(flipbooks count: Int) -> [LeeoTipMoment] {
        flipbooks.filter { count >= $0 }.map { threshold in
            LeeoTipMoment(id: "flipbooks.\(threshold)",
                          message: String(localized: "지금까지 플립북 \(count)편을 완성했어요",
                                          comment: "Tip ask card: how many flipbooks the family finished and saved to Photos"))
        }
    }

    static var reachedNow: [LeeoTipMoment] {
        reached(flipbooks: LeeoEngagement.shared.significantEventCount)
    }
}

/// 이용권·선물 바로 아래: 고마운 순간의 부탁 카드(이미 Pro 를 가진 어른에게만)와 '개발자 응원하기' 줄.
///
/// 카드는 아이 화면이 아니라 어른 확인을 지난 여기에만 선다 — 아이가 결제 화면에 닿지 않게.
/// 얼마나 드물게 물을지는 LeeoKit 규칙(`LeeoTipAskPolicy`)이 정한다.
/// ⚠️ 줄과 카드는 팁 상품이 App Store 에서 와야 선다.
private struct TipRows: View {
    @ObservedObject var tipJar: LeeoTipJar
    let hasPro: Bool

    var body: some View {
        // 상품이 없으면 빈 칸도 남기지 않는다.
        if tipJar.isAvailable {
            // 아직 안 산 사람에게는 이용권이 맞는 길이라 묻지 않는다.
            if hasPro {
                Section {
                    LeeoTipAskSlot<RotoscopeiPadSpec>(tipJar: tipJar, reached: PalangTipMoments.reachedNow)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                LeeoTipJarLink<RotoscopeiPadSpec>(tipJar: tipJar)
            }
        }
    }
}
