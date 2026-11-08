import SwiftUI
import LeeoKit

/// The purchase screen's swipeable pictures (LeeoKit `LeeoShowcase`): each
/// pass benefit drawn as what it looks like, so a parent gets it at a glance.
///
/// Drawn in SwiftUI from the app's own guide drawings rather than screenshots,
/// so they follow the language and dark mode and cost no app size. No words
/// inside the pictures — the line under each one says it.
enum PaywallShowcases {
    /// Every benefit, the one the kid just bumped into first.
    static func all(first reason: LockReason) -> [LeeoShowcase] {
        let items = [
            LeeoShowcase(id: LockReason.presets.rawValue,
                         title: String(localized: "따라 그리기 \(PresetLibrary.all.count)세트 전부, 앞으로 나올 세트도"),
                         detail: "") { Fitted { PresetsArt() } },
            LeeoShowcase(id: LockReason.projects.rawValue,
                         title: String(localized: "작품을 개수 제한 없이 보관"),
                         detail: "") { Fitted { ProjectsArt() } },
            LeeoShowcase(id: LockReason.pages.rawValue,
                         title: String(localized: "빈 종이 플립북 장수 제한 없음"),
                         detail: "") { Fitted { PagesArt() } },
            LeeoShowcase(id: LockReason.video.rawValue,
                         title: String(localized: "내 동영상으로 그리기 무제한"),
                         detail: "") { Fitted { VideoArt() } },
            LeeoShowcase(id: LockReason.recording.rawValue,
                         title: String(localized: "목소리 녹음 시간 제한 없음"),
                         detail: "") { Fitted { RecordingArt() } },
            LeeoShowcase(id: "endCard",
                         title: String(localized: "저장한 영상 끝에 팔랑북 카드 없음"),
                         detail: "") { Fitted { EndCardArt() } }
        ]
        return items.filter { $0.id == reason.rawValue } + items.filter { $0.id != reason.rawValue }
    }
}

// MARK: - Pieces

/// Draws a picture at its iPad size and shrinks it to fit a phone's card.
private struct Fitted<Art: View>: View {
    @ViewBuilder let art: Art
    private let designWidth: CGFloat = 470

    var body: some View {
        GeometryReader { geo in
            art
                .frame(width: designWidth, height: geo.size.height)
                .scaleEffect(min(1, geo.size.width / designWidth))
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private let crayons: [Color] = [.orange, .pink, .blue, .green, .purple, .red]

/// A guide drawing on white paper — as the guide (blue-grey) or, given a
/// color, as if a kid had drawn it in crayon.
private struct Sheet: View {
    let preset: Int
    var crayon: Color?
    var width: CGFloat = 96

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white)
            .frame(width: width, height: width * 3 / 4)
            .overlay { drawing.padding(4) }
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    @ViewBuilder
    private var drawing: some View {
        let all = PresetLibrary.all
        if !all.isEmpty, let ui = all[preset % all.count].thumbnail {
            if let crayon {
                Image(uiImage: ui).resizable().renderingMode(.template).scaledToFit().foregroundStyle(crayon)
            } else {
                Image(uiImage: ui).resizable().scaledToFit()
            }
        }
    }
}

/// The ∞ in an orange circle: no limit.
private struct InfinityBadge: View {
    var body: some View {
        Image(systemName: "infinity")
            .font(.title2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(Color.orange, in: Circle())
            .shadow(color: .orange.opacity(0.4), radius: 6, y: 2)
            .padding(12)
    }
}

// MARK: - Pictures

/// Every tracing set, side by side.
private struct PresetsArt: View {
    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<4, id: \.self) { col in Sheet(preset: row * 4 + col) }
                }
            }
        }
    }
}

/// A shelf of colorful works, and ∞.
private struct ProjectsArt: View {
    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in
                        let i = row * 3 + col
                        Sheet(preset: i + 2, crayon: crayons[i], width: 112)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { InfinityBadge() }
    }
}

/// A fanned stack of flipbook pages, and ∞.
private struct PagesArt: View {
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Sheet(preset: 1, crayon: i == 4 ? .orange : nil, width: 200)
                    .opacity(i == 4 ? 1 : 0.5)
                    .rotationEffect(.degrees(Double(i - 4) * 4), anchor: .bottomLeading)
                    .offset(x: CGFloat(4 - i) * -6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { InfinityBadge() }
    }
}

/// A clip from the camera roll becomes a drawing.
private struct VideoArt: View {
    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [.teal, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 160, height: 120)
                .overlay {
                    Image(systemName: "figure.run")
                        .font(.system(size: 56))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(8)
                }
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            Image(systemName: "arrow.right")
                .font(.title2.weight(.bold))
                .foregroundStyle(.orange)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white)
                .frame(width: 160, height: 120)
                .overlay {
                    Image(systemName: "figure.run")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.orange)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil.tip")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .padding(8)
                }
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
    }
}

/// A mic and a long voice wave, and ∞.
private struct RecordingArt: View {
    private let levels: [CGFloat] = [0.3, 0.6, 0.9, 0.5, 0.75, 1, 0.45, 0.8, 0.35, 0.65, 0.9, 0.5, 0.3, 0.7, 0.55, 0.85]

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(Color.orange, in: Circle())
            HStack(spacing: 5) {
                ForEach(levels.indices, id: \.self) { i in
                    Capsule().fill(Color.orange.opacity(0.75)).frame(width: 7, height: 90 * levels[i])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { InfinityBadge() }
    }
}

/// A saved flipbook ends on the kid's last drawing — the app's card is gone.
private struct EndCardArt: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in Sheet(preset: 2, crayon: crayons[i], width: 100) }
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.15))
                .frame(width: 100, height: 75)
                .overlay {
                    Image(systemName: "book.pages.fill")
                        .font(.title)
                        .foregroundStyle(.orange.opacity(0.4))
                }
                .overlay {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white, .red)
                }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
