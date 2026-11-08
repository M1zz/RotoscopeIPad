import SwiftUI
import LeeoKit

struct RotoscopeiPadSupportView: View {
    @EnvironmentObject private var store: LeeoStore
    @State private var showUnlock = false
    /// Kids can reach the gear, so feedback, reviews and web links wait
    /// behind the same grown-up check as the purchase screen.
    @State private var parentVerified = false
    @Environment(\.dismiss) private var dismiss
    @State private var workCount = RotoProject.listProjects().count

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
                // 요금제 → 응원 → 선물 → 구매 복원, one place for everything that costs money.
                Section {
                    if store.hasPro {
                        Label("모든 기능이 열려 있어요", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button { showUnlock = true } label: {
                            Label("평생 이용권", systemImage: "star.fill")
                        }
                    }
                    // The supporter badge rides on this row (LeeoTipJarLink).
                    if let tipJar = store.tipJar {
                        TipLink(tipJar: tipJar)
                    }
                    if let gift = store.gift {
                        GiftRow(gift: gift, hasPro: store.hasPro)
                    }
                    // A family with the pass has nothing to restore; everyone else finds it last.
                    if !store.hasPro {
                        Button {
                            Task { await store.restore() }
                        } label: {
                            if store.isRestoring {
                                ProgressView()
                            } else {
                                Label("구매 복원", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(store.isRestoring)
                    }
                } header: { Text("요금제와 응원") }
                if let tipJar = store.tipJar, store.hasPro {
                    TipAskCard(tipJar: tipJar)
                }
                // Kids fill the home grid fast; a grown-up clears many works at once here.
                Section {
                    NavigationLink { WorksManagerView() } label: {
                        LabeledContent {
                            Text(verbatim: "\(workCount)")
                        } label: {
                            Label("작품 정리", systemImage: "square.grid.2x2")
                        }
                    }
                } header: { Text("내 작품") }
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
            .onReceive(NotificationCenter.default.publisher(for: RotoProject.projectsDidChange)) { _ in
                workCount = RotoProject.listProjects().count
            }
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

/// One "Gift Pro" row → the gift page; entering a code someone sent sits at
/// the bottom of that page. Same shape as 클립키보드's settings.
///
/// The sender buys a consumable gift and shares an App Store offer-code link;
/// the App Store unlocks the lifetime pass (`RotoscopeiPadSpec.monetization.gift`).
/// Titles and screens come from LeeoKit (`LeeoGiftText`), already in every language.
/// ⚠️ The row appears once the gift product loads, or while there's a sent or
///    pending gift to look back at, or a code to enter — never a dead row.
/// ⚠️ `LeeoGiftStore` is observed on its own: the product arrives after
///    launch and `LeeoStore` doesn't republish that change.
private struct GiftRow: View {
    @ObservedObject var gift: LeeoGiftStore
    let hasPro: Bool
    @State private var showSupport = false

    private var canSend: Bool { gift.isAvailable || gift.pendingCount > 0 || !gift.sentGifts.isEmpty }
    /// Only someone without the pass has a code to enter.
    private var canRedeem: Bool { gift.canRedeem && !hasPro }

    var body: some View {
        if canSend || canRedeem {
            NavigationLink {
                page
                    // If a gift gets stuck, the bug report carries the payment and code.
                    .sheet(isPresented: $showSupport) {
                        NavigationStack {
                            LeeoFeedbackView<RotoscopeiPadSpec>(initialType: .bug, extraInfo: gift.supportLines,
                                                                initialCategory: .purchase)
                        }
                    }
            } label: {
                Label(LeeoGiftText.sendEntry, systemImage: "gift.fill")
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        if canSend {
            LeeoGiftView<RotoscopeiPadSpec>(gift: gift, showsRedeemLink: canRedeem,
                                            onContactSupport: { showSupport = true })
        } else {
            LeeoGiftRedeemView<RotoscopeiPadSpec>(gift: gift, onContactSupport: { showSupport = true })
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

/// '개발자 응원하기' 줄. 상품이 App Store 에서 와야 선다 — 없으면 빈 줄도 남기지 않는다.
private struct TipLink: View {
    @ObservedObject var tipJar: LeeoTipJar

    var body: some View {
        if tipJar.isAvailable {
            LeeoTipJarLink<RotoscopeiPadSpec>(tipJar: tipJar)
        }
    }
}

/// 고마운 순간의 부탁 카드. 이미 Pro 를 가진 어른에게만, 어른 확인을 지난 여기에만 선다
/// (아직 안 산 사람에게는 이용권이 맞는 길이라 묻지 않는다).
/// 얼마나 드물게 물을지는 LeeoKit 규칙(`LeeoTipAskPolicy`)이 정한다.
private struct TipAskCard: View {
    @ObservedObject var tipJar: LeeoTipJar

    var body: some View {
        if tipJar.isAvailable {
            Section {
                LeeoTipAskSlot<RotoscopeiPadSpec>(tipJar: tipJar, reached: PalangTipMoments.reachedNow)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }
}
