import SwiftUI

/// First-launch guide: three big pictures that mirror the real buttons
/// (same symbols, same colors), with one short line each for the grown-up
/// reading along. Shown once, only to a fresh install with no works yet.
struct FirstRunOnboardingView: View {
    /// Persisted by the caller; flipped when the guide is finished or skipped.
    @Binding var hasSeenOnboarding: Bool
    @State private var page = 0

    private struct Step {
        let symbols: [(name: String, color: Color)]
        let caption: LocalizedStringKey
    }

    private let steps: [Step] = [
        Step(symbols: [("video.fill", .green),
                       ("pencil.and.outline", .gray),
                       ("pencil.tip.crop.circle.badge.plus", .orange)],
             caption: "동영상, 빈 종이, 따라 그리기 중에서 골라 시작해요"),
        Step(symbols: [("paintbrush.pointed.fill", .accentColor),
                       ("pencil.and.outline", .orange),
                       ("arrow.right", .orange)],
             caption: "한 장을 그리고 주황 버튼을 누르면 다음 장을 그려요"),
        Step(symbols: [("play.fill", .accentColor),
                       ("mic.fill", .purple),
                       ("square.and.arrow.down.fill", .green)],
             caption: "재생하면 그림이 팔랑팔랑 움직여요. 목소리를 넣고 사진 앱에 저장해요")
    ]

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Spacer()
                Button { finish() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text("닫기"))
            }

            TabView(selection: $page) {
                ForEach(steps.indices, id: \.self) { i in
                    stepView(steps[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < steps.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Image(systemName: page < steps.count - 1 ? "arrow.right" : "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .frame(width: 160, height: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(page < steps.count - 1 ? .accentColor : .green)
            .accessibilityLabel(page < steps.count - 1 ? Text("다음") : Text("시작하기"))
        }
        .padding(32)
    }

    private func stepView(_ step: Step) -> some View {
        VStack(spacing: 40) {
            Spacer(minLength: 0)
            HStack(spacing: 36) {
                ForEach(step.symbols.indices, id: \.self) { i in
                    Image(systemName: step.symbols[i].name)
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(step.symbols[i].color)
                        .frame(width: 140, height: 140)
                        .background(RoundedRectangle(cornerRadius: 28)
                            .fill(step.symbols[i].color.opacity(0.12)))
                }
            }
            .accessibilityHidden(true)
            Text(step.caption)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 48)   // room for the page dots
    }

    private func finish() {
        hasSeenOnboarding = true
    }
}
