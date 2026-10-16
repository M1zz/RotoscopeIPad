import SwiftUI
import StoreKit
import LeeoKit

/// What a kid sees on hitting a locked thing: a big lock, then a grown-up
/// question, and only past that the purchase screen. Kids never land on a
/// price by themselves.
struct UnlockSheet: View {
    let reason: LockReason

    @EnvironmentObject private var store: LeeoStore
    @Environment(\.dismiss) private var dismiss
    @State private var parentVerified = Screenshot.paywallPrice != nil

    var body: some View {
        Group {
            if parentVerified {
                PurchaseView(reason: reason)
            } else {
                ParentGateView(icon: reason.icon) {
                    withAnimation { parentVerified = true }
                }
            }
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
        .onChange(of: store.hasPro) { _, pro in
            if pro { dismiss() }
        }
        .modifier(PageSizedSheet())
    }
}

/// On iPad the default form sheet is too short for the purchase screen, so
/// the price terms and legal links ended up below the fold. A page-sized
/// sheet shows everything at once.
private struct PageSizedSheet: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}

// MARK: - Parent gate

/// A multiplication a pre-reader can't do, answered on a keypad so guessing
/// doesn't work. A wrong answer swaps in a new question. Guards everything
/// meant for grown-ups: purchases, and Settings (feedback, reviews, web links).
struct ParentGateView: View {
    /// Big picture of what's behind the gate, so the kid knows why it stopped.
    let icon: String
    let onPass: () -> Void

    @State private var a = Int.random(in: 6...9)
    @State private var b = Int.random(in: 6...9)
    @State private var answer = ""
    @State private var shake = 0

    var body: some View {
        VStack(spacing: 28) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 72))
                    .foregroundStyle(.orange)
                    .padding(28)
                    .background(Circle().fill(Color.orange.opacity(0.12)))
                Image(systemName: "lock.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(Color.gray))
            }
            .padding(.top, 40)

            VStack(spacing: 8) {
                Text("어른에게 보여 주세요")
                    .font(.title2.bold())
                Text("보호자 확인: 아래 문제의 답을 눌러 주세요.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Text(verbatim: "\(a) × \(b) =")
                Text(answer.isEmpty ? "?" : answer)
                    .frame(minWidth: 80)
                    .foregroundStyle(answer.isEmpty ? .secondary : .primary)
            }
            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
            .modifier(Shake(animatableData: CGFloat(shake)))

            keypad
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var keypad: some View {
        let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "✓"]]
        return VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            Group {
                                switch key {
                                case "⌫": Image(systemName: "delete.left")
                                        .accessibilityLabel(Text("한 칸 지우기"))
                                case "✓": Image(systemName: "checkmark")
                                        .accessibilityLabel(Text("확인"))
                                default: Text(key)
                                }
                            }
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .frame(width: 88, height: 64)
                        }
                        .buttonStyle(.bordered)
                        .tint(key == "✓" ? .green : .primary)
                    }
                }
            }
        }
    }

    private func press(_ key: String) {
        switch key {
        case "⌫":
            if !answer.isEmpty { answer.removeLast() }
        case "✓":
            if Int(answer) == a * b {
                onPass()
            } else {
                withAnimation(.default) { shake += 1 }
                answer = ""
                a = Int.random(in: 6...9)
                b = Int.random(in: 6...9)
            }
        default:
            if answer.count < 3 { answer += key }
        }
    }
}

private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 12 * sin(animatableData * .pi * 4), y: 0))
    }
}

// MARK: - Purchase (parent-facing)

private struct PurchaseView: View {
    let reason: LockReason

    @EnvironmentObject private var store: LeeoStore
    // Passing the environment's purchase action lets StoreKit find the right
    // window on iPad — the bare Product.purchase() fails there (review 2.1(b)).
    @Environment(\.purchase) private var purchaseAction

    private static let benefits: [(icon: String, text: String)] = [
        ("pencil.tip.crop.circle.badge.plus", String(localized: "따라 그리기 \(PresetLibrary.all.count)세트 전부, 앞으로 나올 세트도")),
        ("square.grid.2x2.fill", String(localized: "작품을 개수 제한 없이 보관")),
        ("book.pages.fill", String(localized: "빈 종이 플립북 장수 제한 없음")),
        ("video.fill", String(localized: "내 동영상으로 그리기 무제한")),
        ("mic.fill", String(localized: "목소리 녹음 시간 제한 없음")),
        ("film", String(localized: "저장한 영상 끝에 팔랑북 카드 없음"))
    ]

    var body: some View {
        // Centered in the page-sized iPad sheet; scrolls when it doesn't fit.
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.orange)
                            .padding(.top, 36)
                        Text("팔랑북 평생 이용권")
                            .font(.largeTitle.bold())
                        Text(reason.message)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Self.benefits, id: \.text) { item in
                            HStack(spacing: 14) {
                                Image(systemName: item.icon)
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                                    .frame(width: 32)
                                Text(item.text)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.orange.opacity(0.08)))

                    purchaseSection

                    VStack(spacing: 10) {
                        Button {
                            Task { await store.restore() }
                        } label: {
                            if store.isRestoring { ProgressView() } else { Text("구매 복원") }
                        }
                        .disabled(store.isRestoring)

                        Text("한 번만 결제하고 구독이 아니에요. 결제는 App Store 계정으로 청구됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 16) {
                            Link("개인정보처리방침", destination: RotoscopeiPadSpec.legal.privacyURL)
                            if let terms = RotoscopeiPadSpec.legal.termsURL {
                                Link("이용약관", destination: terms)
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
        .task { await store.loadProducts() }
    }

    @ViewBuilder
    private var purchaseSection: some View {
        if let product = store.products.first {
            purchaseControls(price: product.displayPrice,
                             familyShareable: product.isFamilyShareable) {
                Task { await store.purchase(product) { try await purchaseAction($0) } }
            }
        } else if let price = Screenshot.paywallPrice {
            // Store review screenshot: the product isn't in App Store Connect
            // yet, so the simulator can't load it — show the price it'll have.
            purchaseControls(price: price, familyShareable: true, showError: false) {}
        } else if store.isLoadingProducts {
            ProgressView().padding(.vertical, 24)
        } else {
            VStack(spacing: 12) {
                Text(store.lastError ?? String(localized: "상품을 불러오지 못했어요."))
                    .foregroundStyle(.secondary)
                Button("다시 시도") { Task { await store.loadProducts() } }
            }
            .padding(.vertical, 16)
        }
    }

    private func purchaseControls(price: String, familyShareable: Bool,
                                  showError: Bool = true,
                                  buy: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Button(action: buy) {
                Group {
                    if store.purchasingProductID != nil {
                        ProgressView().tint(.white)
                    } else {
                        Text("\(price) · 한 번 결제로 평생")
                            .font(.title3.bold())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.orange))
                .foregroundStyle(.white)
            }
            .disabled(store.purchasingProductID != nil)

            if familyShareable {
                Label("가족 공유로 온 가족 아이패드에서 함께 써요", systemImage: "person.3.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if showError, let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Store screenshots

/// Debug-only launch options for App Store screenshots. Release builds
/// compile these to nil, so the real app can't skip the grown-up check.
enum Screenshot {
    /// `-ScreenshotPaywall '$9.99'` opens the purchase screen straight away
    /// (past the grown-up check) showing that price — the in-app purchase
    /// review screenshot (scripts/capture_paywall_screenshot.sh).
    static var paywallPrice: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "ScreenshotPaywall")
        #else
        nil
        #endif
    }
}
