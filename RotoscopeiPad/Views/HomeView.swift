import SwiftUI
import LeeoKit

/// Icon-only home screen: every card sits in one grid. When everything fits
/// the grid fills the screen with no scrolling at all; only when there are
/// more projects than cells does the grid scroll vertically.
struct HomeView: View {
    @EnvironmentObject var project: RotoProject
    @EnvironmentObject var store: LeeoStore
    @State private var projects: [URL] = []
    @State private var lock: LockReason?

    /// Everything shown on the home grid, in display order.
    private enum Item: Identifiable {
        case camera            // shoot a new video
        case video             // pick a video from Photos
        case link              // paste a video URL (parent enters it)
        case blank             // 빈 화면: empty white flipbook, no video
        case preset(GuidePreset)
        case project(URL)

        var id: String {
            switch self {
            case .camera: return "camera"
            case .video: return "video"
            case .link: return "link"
            case .blank: return "blank"
            case .preset(let p): return "preset-\(p.id)"
            case .project(let url): return url.path
            }
        }
    }

    private var items: [Item] {
        var list: [Item] = []
        if CameraVideoPicker.isAvailable { list.append(.camera) }
        list.append(.video)
        // Remote kill switch: the link card can be hidden without an update.
        if LeeoRemoteFlags.isEnabled(PalangFlag.videoLinkImport) { list.append(.link) }
        list.append(.blank)
        list += PresetLibrary.all.map { .preset($0) }
        list += projects.map { .project($0) }
        return list
    }

    private struct GridLayout {
        var columns: Int
        var fitRows: Int      // rows that fit on screen without scrolling
        var cellHeight: CGFloat
    }

    private let cellSpacing: CGFloat = 20
    private let outerPadding: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let all = items
            let layout = gridLayout(for: geo.size)

            if all.count <= layout.columns * layout.fitRows {
                // Everything fits: a fixed grid fills the screen, no scrolling.
                fixedGrid(all, layout: layout)
                    .padding(outerPadding)
                    .frame(width: geo.size.width, height: geo.size.height)
            } else {
                // Too many projects for one screen: same cells, scrolls.
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(),
                                                                 spacing: cellSpacing),
                                             count: layout.columns),
                              spacing: cellSpacing) {
                        ForEach(all) { item in
                            cell(item)
                                .frame(height: layout.cellHeight)
                        }
                    }
                    .padding(outerPadding)
                }
            }
        }
        .onAppear { projects = RotoProject.listProjects() }
        .sheet(isPresented: $project.showLinkImport) {
            VideoLinkImportSheet()
        }
        .sheet(item: $lock) { reason in
            UnlockSheet(reason: reason)
        }
        .fullScreenCover(isPresented: $project.showCameraPicker) {
            CameraVideoPicker(isPresented: $project.showCameraPicker,
                              onPick: { url in project.load(url: url) })
            .ignoresSafeArea()
        }
    }

    // MARK: - Grid geometry

    /// Fits as many equal cells as the screen allows.
    private func gridLayout(for size: CGSize) -> GridLayout {
        let width = max(size.width - outerPadding * 2, 200)
        let columns = max(2, Int((width + cellSpacing) / (230 + cellSpacing)))
        let cellW = (width - cellSpacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cellH = cellW * 0.72
        let height = max(size.height - outerPadding * 2, 1)
        let fitRows = max(1, Int((height + cellSpacing) / (cellH + cellSpacing)))
        return GridLayout(columns: columns, fitRows: fitRows, cellHeight: cellH)
    }

    /// The no-scroll layout: rows stretch so the cells fill the screen.
    private func fixedGrid(_ all: [Item], layout: GridLayout) -> some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<layout.fitRows, id: \.self) { row in
                HStack(spacing: cellSpacing) {
                    ForEach(0..<layout.columns, id: \.self) { col in
                        let i = row * layout.columns + col
                        Group {
                            if i < all.count {
                                cell(all[i])
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func cell(_ item: Item) -> some View {
        switch item {
        case .camera:
            createCell("camera.fill", tint: .blue, label: "동영상 찍기", locked: !videoAllowed) {
                startVideo { project.showCameraPicker = true }
            }
        case .video:
            createCell("video.fill", tint: .green, label: "사진에서 동영상 가져오기",
                       locked: !videoAllowed) {
                startVideo { project.showPhotoPicker = true }
            }
        case .link:
            createCell("link", tint: .indigo, label: "동영상 링크 열기", locked: !videoAllowed) {
                startVideo { project.showLinkImport = true }
            }
        case .blank:
            blankCell
        case .preset(let preset):
            let locked = !FreeTier.isFree(preset) && !store.gate.allows(FreeTier.premiumPresetKey)
            Button {
                if locked {
                    lock = .presets
                } else if canAddProject() {
                    project.createFromPreset(preset)
                }
            } label: {
                presetCard(preset, locked: locked)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("따라 그리기 \(presetNumber(preset))"))
            .accessibilityValue(locked ? Text("잠김") : Text(verbatim: ""))
        case .project(let dir):
            Button { project.openProject(at: dir) } label: {
                thumbnail(for: dir)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("내 작품"))
            .accessibilityHint(Text("길게 누르면 지울 수 있어요"))
            .contextMenu {
                // Long-press → red trash to delete.
                Button(role: .destructive) {
                    RotoProject.deleteProject(at: dir)
                    projects = RotoProject.listProjects()
                } label: {
                    Label("지우기", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Free tier

    /// The free video import is still unused (or everything is unlocked).
    private var videoAllowed: Bool {
        store.gate.evaluate(FreeTier.videoImportKey,
                            current: FreeTier.videoImportsUsed).isAllowed
    }

    /// Room for one more saved work; otherwise brings up the unlock sheet.
    private func canAddProject() -> Bool {
        if store.gate.evaluate(FreeTier.projectKey, current: projects.count).isAllowed {
            return true
        }
        lock = .projects
        return false
    }

    private func startVideo(_ open: () -> Void) {
        guard videoAllowed else { lock = .video; return }
        if canAddProject() { open() }
    }

    private func lockBadge() -> some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .padding(8)
            .background(Circle().fill(Color.gray))
            .padding(8)
    }

    /// 1-based position of a guide set on the home grid, for VoiceOver.
    private func presetNumber(_ preset: GuidePreset) -> Int {
        (PresetLibrary.all.firstIndex { $0.id == preset.id } ?? 0) + 1
    }

    private func createCell(_ symbol: String, tint: Color, label: LocalizedStringKey,
                            locked: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 44))
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .bold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .overlay(alignment: .topTrailing) {
            if locked { lockBadge() }
        }
        .accessibilityLabel(Text(label))
        .accessibilityValue(locked ? Text("잠김") : Text(verbatim: ""))
    }

    /// 빈 화면: a plain white page with a big plus — a new project that starts
    /// from nothing, just empty pages to draw on.
    private var blankCell: some View {
        Button { if canAddProject() { project.createBlank() } } label: {
            ZStack {
                Color.white
                VStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 52, weight: .bold))
                    Image(systemName: "pencil.and.outline")
                        .font(.system(size: 30))
                }
                .foregroundStyle(Color.gray.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.gray.opacity(0.45),
                              style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("빈 종이 플립북 만들기"))
    }

    /// A guide set card: the mid-animation pose on a white page, with a
    /// dashed border and a pencil badge that say "trace me" without words.
    private func presetCard(_ preset: GuidePreset, locked: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Color.white
                .overlay {
                    if let thumb = preset.thumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(10)
                    }
                }
            if locked {
                lockBadge()
            } else {
                Image(systemName: "pencil.tip.crop.circle.badge.plus")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, .orange)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.orange.opacity(0.6),
                          style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
    }

    private func thumbnail(for dir: URL) -> some View {
        let thumbPath = dir.appendingPathComponent("thumb.png").path
        return Group {
            if let ui = UIImage(contentsOfFile: thumbPath) {
                Color.clear
                    .overlay(
                        Image(uiImage: ui)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
            } else {
                Image(systemName: "film")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
