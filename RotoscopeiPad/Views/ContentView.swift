import SwiftUI
import LeeoKit
import TipKit

/// Icon-only UI for pre-readers: no text anywhere.
/// One row of tools on top, the canvas, and play controls at the bottom.
struct ContentView: View {
    @EnvironmentObject var project: RotoProject
    @EnvironmentObject var store: LeeoStore
    @State private var lock: LockReason?
    @State private var showGiftShot = false
    @State private var showDone = false
    /// The trash asks first: a big O to wipe the page, a big X to keep it.
    @State private var askClear = false
    @AppStorage(Flipbooks.key) private var flipbooksOpen = false
    /// The stamps a grown-up picked in Settings (at most 10).
    @AppStorage(StampShape.storageKey) private var stampIDs = StampShape.starterIDs
    private var stamps: [StampShape] { StampShape.chosen(stampIDs) }
    @State private var restoredLastProject = false
    @State private var showPageFlash = false
    @State private var pageFlashTask: Task<Void, Never>?
    @State private var showTransport = true
    @State private var showSupport = false
    @State private var showOnboarding = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone (and a narrow iPad window): rows split up, stamps go under the canvas.
    private var isCompact: Bool { sizeClass == .compact }
    private let nextPageTip = NextPageTip()
    @ObservedObject private var shortcuts = ShortcutRouter.shared
    private let dubTip = DubTip()

    var body: some View {
        screen
        // Settings gear, shown on the home screen so it never covers the canvas.
        .overlay(alignment: .topTrailing) { settingsGear }
        .sheet(isPresented: $showSupport) {
            RotoscopeiPadSupportView()
        }
        .fullScreenCover(isPresented: $showOnboarding,
                         onDismiss: { hasSeenOnboarding = true }) {
            FirstRunOnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
        }
        .onChange(of: hasSeenOnboarding) { _, seen in
            if seen { showOnboarding = false }
        }
        .onReceive(shortcuts.$pending.compactMap { $0 }) { request in
            handleShortcut(request)
        }
        .sheet(isPresented: $project.showPhotoPicker) {
            PhotosVideoPicker(isPresented: $project.showPhotoPicker,
                              onPick: { url in project.load(url: url) })
            .ignoresSafeArea()
        }
        .sheet(item: $lock) { reason in
            UnlockSheet(reason: reason)
        }
        .sheet(isPresented: $showGiftShot) { giftShot }
        .onChange(of: project.recordingLimitReached) { _, reached in
            guard reached else { return }
            project.recordingLimitReached = false
            lock = .recording
        }
        .overlay { pageFlashOverlay }
        .overlay { exportOverlay }
        .overlay { clearAskOverlay }
        .onChange(of: project.currentFrame) {
            guard project.isOpen, !project.isPlaying else { return }
            flashPageNumber()
        }
        .onAppear(perform: restoreOnLaunch)
        // Drawing: the whole screen is the page — no status bar, and a stroke
        // near the bottom edge doesn't throw the kid out of the app.
        .statusBarHidden(project.isOpen)
        .defersSystemGestures(on: project.isOpen ? .bottom : [])
    }

    /// The editor while a work is open, the home grid otherwise.
    private var screen: some View {
        VStack(spacing: 0) {
            if project.isOpen {
                toolbar
                Divider()
                canvasArea
                // A sketchbook is one page: nothing to turn or play.
                if showsTransport {
                    Divider()
                    transport
                }
            } else {
                HomeView()
            }
        }
    }

    private var showsTransport: Bool { showTransport && !project.isSketchbook }

    @ViewBuilder
    private var settingsGear: some View {
        if !project.isOpen {
            Button { showSupport = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 26))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("설정"))
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
    }

    /// Debug-only gift review screenshot (`-ScreenshotGift`).
    @ViewBuilder
    private var giftShot: some View {
        if let gift = store.gift, let price = Screenshot.giftPrice {
            NavigationStack { LeeoGiftView<RotoscopeiPadSpec>(previewPrice: price, gift: gift) }
        }
    }

    /// Come back right where you left off — once per launch.
    private func restoreOnLaunch() {
        guard !restoredLastProject else { return }
        restoredLastProject = true
        #if DEBUG
        // Store screenshots of the home grid (scripts/capture_screenshots.sh).
        if ProcessInfo.processInfo.arguments.contains("-ScreenshotHome") { return }
        // A fresh sketchbook, shaped to this screen (`-ScreenshotSketchbook`).
        if ProcessInfo.processInfo.arguments.contains("-ScreenshotSketchbook") {
            project.createBlank()
            // `-ScreenshotTool 지우개` starts on that tool (store shots of each tool's color).
            if let name = UserDefaults.standard.string(forKey: "ScreenshotTool"),
               let tool = ToolMode(rawValue: name) { project.tool = tool }
            return
        }
        #endif
        if Screenshot.paywallPrice != nil {
            lock = .general
            return
        }
        if Screenshot.giftPrice != nil {
            showGiftShot = true
            return
        }
        let saved = RotoProject.listProjects()
        // First run: a short picture guide. Anyone who already has works
        // knows the app, so they never see it.
        // The guide is about flipbooks; a sketchbook needs none.
        if saved.isEmpty, !hasSeenOnboarding, flipbooksOpen {
            showOnboarding = true
        } else if !hasSeenOnboarding {
            hasSeenOnboarding = true
        }
        if let last = saved.first {
            project.openProject(at: last)
        }
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        ZStack(alignment: .bottomTrailing) {
            // Around a page that isn't the screen's shape: a soft desk, not black.
            CanvasView()
                .background(Color(uiColor: .systemGray6))
                // With no play bar below, the page runs to the bottom edge.
                .ignoresSafeArea(.container, edges: showsTransport ? [] : .bottom)

            // Bring the hidden play bar back.
            if !showTransport, !project.isSketchbook {
                Button {
                    withAnimation { showTransport = true }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 64, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
                .accessibilityLabel(Text("재생 막대 보이기"))
                .padding(14)
            }
        }
    }

    // MARK: - Page flash: big "4 / 32" in the middle when turning pages

    private func flashPageNumber() {
        pageFlashTask?.cancel()
        withAnimation(.easeOut(duration: 0.1)) { showPageFlash = true }
        pageFlashTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) { showPageFlash = false }
        }
    }

    @ViewBuilder
    private var pageFlashOverlay: some View {
        if showPageFlash {
            Text(verbatim: "\(project.currentFrame + 1)\u{2009}/\u{2009}\(project.frameCount)")
                .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 36)
                .padding(.vertical, 20)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Toolbar
    // Grouped by what the kid means to do, each group in its own tray:
    // leave (home) · draw and wipe · make it move (flipbooks only) · keep (save),
    // then what the line looks like — color and size.

    private var toolbar: some View {
        VStack(spacing: 8) {
            if isCompact {
                compactRows
            } else {
                // One row whenever it fits (most iPads), so the page gets the most room.
                ViewThatFits(in: .horizontal) {
                    oneRow
                    VStack(spacing: 8) {
                        toolRow
                        HStack(spacing: 6) {
                            looksTray
                            if !project.isSketchbook { moveTools.toolTray() }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, isCompact ? 8 : 10)
    }

    /// Everything in one line: home · draw · stamps · looks · move · save.
    private var oneRow: some View {
        HStack(spacing: 6) {
            iconButton("house.fill", label: "홈으로") { project.goHome() }
            Spacer(minLength: 0)
            drawTools.toolTray()
            if !stamps.isEmpty { stampGrid.toolTray() }
            looksTray
            if !project.isSketchbook { moveTools.toolTray() }
            Spacer(minLength: 0)
            exportButton
        }
    }

    /// Too narrow for one line: home · draw · stamps · save, then looks and move.
    private var toolRow: some View {
        HStack(spacing: 6) {
            iconButton("house.fill", label: "홈으로") { project.goHome() }
            Spacer(minLength: 0)
            drawTools.toolTray()
            if !stamps.isEmpty { stampGrid.toolTray() }
            Spacer(minLength: 0)
            exportButton
        }
    }

    /// The colors: a paint box on iPad, one rainbow line on a phone.
    @ViewBuilder
    private var looksTray: some View {
        if isCompact {
            HStack(spacing: 0) {
                ForEach(RotoProject.palette, id: \.self) { colorDot($0).frame(maxWidth: .infinity) }
            }
            .toolTray()
        } else {
            colorPalette.toolTray()
        }
    }

    /// The colors stacked like a paint box, five over five, so one row holds everything.
    private var colorPalette: some View {
        let palette = RotoProject.palette
        let half = (palette.count + 1) / 2
        return Grid(horizontalSpacing: Bar.gap, verticalSpacing: Bar.gap) {
            GridRow { ForEach(palette.prefix(half), id: \.self) { colorDot($0) } }
            GridRow { ForEach(palette.dropFirst(half), id: \.self) { colorDot($0) } }
        }
    }

    /// A phone: home · draw tray (with sizes) · save, then stamps, colors, and sound and play.
    @ViewBuilder
    private var compactRows: some View {
        HStack(spacing: 0) {
            iconButton("house.fill", label: "홈으로") { project.goHome() }
            Spacer(minLength: 4)
            drawTools.toolTray()
            Spacer(minLength: 4)
            exportButton
        }
        if !stamps.isEmpty {
            HStack(spacing: Bar.gap) {
                ForEach(stamps) { stampButton($0) }
            }
            .toolTray()
        }
        looksTray
        if !project.isSketchbook {
            moveTools.toolTray()
        }
    }

    /// Each tool has its own color; its size dot lights up in the same color,
    /// so a kid sees which size belongs to which tool.
    private func tint(_ tool: ToolMode) -> Color {
        switch tool {
        case .erase: return .orange
        case .stamp: return .purple
        case .move: return .green
        case .brush, .polygon: return .blue
        }
    }

    /// Draw and wipe: pen and eraser with their sizes right beside them,
    /// then the whole-page trash.
    @ViewBuilder
    private var drawTools: some View {
        toolButton("paintbrush.pointed.fill", selected: project.tool == .brush, tint: tint(.brush), label: "붓") {
            project.tool = .brush
        }
        toolButton("hand.point.up.left.fill", selected: project.tool == .move, tint: tint(.move), label: "옮기기") {
            project.tool = .move
        }
        toolButton("eraser.fill", selected: project.tool == .erase, tint: tint(.erase), label: "지우개") {
            project.tool = .erase
        }
        sizeDots
        clearPageButton
    }

    /// Make it move: voice, play, and the video behind the drawing.
    @ViewBuilder
    private var moveTools: some View {
        dubButton
        playButton
        backgroundButton
    }

    /// The size of what the kid is drawing: stamp sizes while stamping.
    @ViewBuilder
    private var sizeDots: some View {
        if project.tool == .stamp {
            ForEach(RotoProject.stampSizePresets, id: \.self) { stampSizeDot($0) }
        } else {
            ForEach(RotoProject.widthPresets, id: \.name) { sizeDot($0.value) }
        }
    }

    // MARK: - Stamps: every shape right on the toolbar — one tap picks it

    /// Two rows, like the colors.
    private var stampGrid: some View {
        let half = (stamps.count + 1) / 2
        return Grid(horizontalSpacing: Bar.gap, verticalSpacing: Bar.gap) {
            GridRow { ForEach(stamps.prefix(half)) { stampButton($0) } }
            GridRow { ForEach(stamps.dropFirst(half)) { stampButton($0) } }
        }
    }

    private func stampButton(_ shape: StampShape) -> some View {
        let selected = project.tool == .stamp && project.stampShape == shape
        return Button {
            project.stampShape = shape
            project.tool = .stamp
        } label: {
            StampGlyph(shape: shape, colorHex: project.brushColorHex)
                .frame(width: Bar.cell(isCompact) * 0.62, height: Bar.cell(isCompact) * 0.62)
                // A phone shares its row among the stamps; an iPad's are square cells.
                .frame(maxWidth: isCompact ? .infinity : Bar.cell(false))
                .frame(height: Bar.cell(isCompact))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? tint(.stamp).opacity(0.22) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tint(.stamp), lineWidth: selected ? 3 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shape.accessibilityName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A stamp size among the size dots.
    private func stampSizeDot(_ value: Double) -> some View {
        let selected = abs(project.stampSize - value) < 0.001
        return Button { project.stampSize = value } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: 6 + value * 60, height: 6 + value * 60)
                .frame(width: Bar.cell(isCompact), height: Bar.cell(isCompact))
        }
        .background(Circle().fill(selected ? tint(project.tool).opacity(0.25) : .clear))
        .accessibilityLabel(Self.stampSizeLabel(value))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var clearPageButton: some View {
        // Wipe the whole page — after the O / X question (no undo).
        Button { withAnimation(.snappy) { askClear = true } } label: {
            Image(systemName: "trash.fill")
                .modifier(ToolIcon())
        }
        .buttonStyle(ToolStyle(fill: .red))
        .accessibilityLabel(Text("이 장 모두 지우기"))
    }

    /// "Wipe this page?" without words: the trash, then O (yes) and X (no).
    @ViewBuilder
    private var clearAskOverlay: some View {
        if askClear {
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy) { askClear = false } }
                VStack(spacing: 32) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                    HStack(spacing: 40) {
                        answerButton("circle", tint: .blue, label: "지우기") {
                            project.clearCurrentMask()
                        }
                        answerButton("xmark", tint: .red, label: "닫기") {}
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func answerButton(_ symbol: String, tint: Color, label: LocalizedStringKey,
                              action: @escaping () -> Void) -> some View {
        Button {
            action()
            withAnimation(.snappy) { askClear = false }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 130, height: 130)
                .background(Circle().fill(tint))
                .shadow(radius: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var dubButton: some View {
        // Dub: animation plays once while the mic records the kid.
        Button {
            dubTip.invalidate(reason: .actionPerformed)
            if project.isRecording {
                project.stopPlayback()
            } else {
                project.startDubbing(limit: FreeTier.recordingLimit(hasPro: store.hasPro))
            }
        } label: {
            Image(systemName: project.isRecording ? "stop.fill" : "mic.fill")
                .modifier(ToolIcon())
                // 보라색만으로 '녹음 있음'을 말하지 않는다.
                .overlay(alignment: .topTrailing) {
                    if differentiateWithoutColor && project.hasAudio && !project.isRecording {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .offset(x: 6, y: -4)
                    }
                }
        }
        .buttonStyle(ToolStyle(fill: project.isRecording ? .red : (project.hasAudio ? .purple : .gray)))
        .accessibilityLabel(project.isRecording ? Text("녹음 멈추기") : Text("목소리 녹음"))
        .accessibilityValue(project.hasAudio && !project.isRecording ? Text("녹음 있음") : Text(verbatim: ""))
        .accessibilityShowsLargeContentViewer()
        .popoverTip(dubTip, arrowEdge: .top)
    }

    private var playButton: some View {
        Button { project.togglePlayback() } label: {
            Image(systemName: project.isPlaying ? "pause.fill" : "play.fill")
                .modifier(ToolIcon())
        }
        .buttonStyle(ToolStyle(fill: .accentColor))
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityLabel(project.isPlaying ? Text("일시정지") : Text("재생"))
        .accessibilityShowsLargeContentViewer()
    }

    @ViewBuilder
    private var backgroundButton: some View {
        // Hide the video background: play/export only the drawing.
        if project.hasVideo {
            Button { project.toggleHideBackground() } label: {
                Image(systemName: project.hideBackground
                      ? "video.slash.fill" : "video.fill")
                    .modifier(ToolIcon())
            }
            .buttonStyle(ToolStyle(fill: project.hideBackground ? .pink : .gray))
            .accessibilityLabel(project.hideBackground
                                ? Text("동영상 배경 보이기") : Text("동영상 배경 숨기기"))
        }
    }

    private var exportButton: some View {
        Button { runExport() } label: {
            Image(systemName: "square.and.arrow.down.fill")
                .modifier(ToolIcon())
        }
        .buttonStyle(ToolStyle(fill: .green))
        .disabled(project.isExporting)
        .accessibilityLabel(Text("사진 앱에 저장"))
        .accessibilityInputLabels([Text("저장"), Text("사진 앱에 저장")])
        .accessibilityShowsLargeContentViewer()
    }

    private func iconButton(_ symbol: String, label: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .modifier(ToolIcon())
        }
        .buttonStyle(ToolStyle(fill: Color.primary.opacity(0.08), ink: .accentColor))
        .accessibilityLabel(Text(label))
        .accessibilityShowsLargeContentViewer()
    }

    private func toolButton(_ symbol: String, selected: Bool, tint: Color, label: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .modifier(ToolIcon())
        }
        .buttonStyle(selected ? ToolStyle(fill: tint.opacity(0.22), ink: tint)
                              : ToolStyle(fill: Color.primary.opacity(0.08), ink: .secondary))
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
    }

    private func colorDot(_ hex: String) -> some View {
        let selected = project.brushColorHex == hex
            && (project.tool == .brush || project.tool == .stamp)
        return Circle()
            .fill(Color(rgbHex: hex))
            // On a phone ten colors share one line, so each is a little smaller.
            .frame(width: isCompact ? 28 : Bar.cell(false), height: isCompact ? 28 : Bar.cell(false))
            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
            .overlay(
                Circle().stroke(Color.accentColor, lineWidth: selected ? 4 : 0)
                    .padding(-4)
            )
            .onTapGesture {
                project.brushColorHex = hex
                // Picking a color means "draw" — always back to the pen.
                project.tool = .brush
            }
            // A bare circle with a tap gesture: tell VoiceOver it's a button.
            .accessibilityElement()
            .accessibilityLabel(Self.colorName(hex))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func sizeDot(_ value: Double) -> some View {
        // The hand has no size: no dot is lit while moving shapes.
        let selected = nearlyEqual(project.brushWidth, value) && project.tool != .move
        return Button { project.brushWidth = value } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: 8 + value * 500, height: 8 + value * 500)
                .frame(width: Bar.cell(isCompact), height: Bar.cell(isCompact))
        }
        .background(
            Circle().fill(selected ? tint(project.tool).opacity(0.25) : .clear)
        )
        .accessibilityLabel(Self.brushSizeLabel(value))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - VoiceOver names
    // The screen has no words for pre-readers, so every icon needs a spoken one.

    private static func colorName(_ hex: String) -> Text {
        switch hex {
        case "FF3B30": return Text("빨강")
        case "FF9500": return Text("주황")
        case "FFCC00": return Text("노랑")
        case "34C759": return Text("초록")
        case "007AFF": return Text("파랑")
        case "3A3FBF": return Text("남색")
        case "AF52DE": return Text("보라")
        case "FF2D55": return Text("분홍")
        case "FFFFFF": return Text("흰색")
        case "000000": return Text("검정")
        default:       return Text(verbatim: "#\(hex)")
        }
    }

    /// Brush presets are ordered thin → thick.
    private static func brushSizeLabel(_ value: Double) -> Text {
        switch RotoProject.widthPresets.firstIndex(where: { abs($0.value - value) < 0.0005 }) {
        case 0:  return Text("가는 붓")
        case 1:  return Text("보통 붓")
        default: return Text("굵은 붓")
        }
    }

    /// Stamp sizes are ordered small → big.
    private static func stampSizeLabel(_ value: Double) -> Text {
        switch RotoProject.stampSizePresets.firstIndex(where: { abs($0 - value) < 0.001 }) {
        case 0:  return Text("작은 도장")
        case 1:  return Text("중간 도장")
        default: return Text("큰 도장")
        }
    }

    private func nearlyEqual(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0005 }

    // MARK: - Transport (frame navigation + play)

    private var transport: some View {
        HStack(spacing: isCompact ? 10 : 18) {
            // "이전 그림" — mirrors the next button, quieter color.
            Button { project.step(by: -1) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                    Image(systemName: "photo")
                }
                .font(.system(size: isCompact ? 20 : 24))
                .frame(width: isCompact ? 60 : 88, height: isCompact ? 44 : 52)
            }
            .buttonStyle(.bordered)
            .disabled(project.currentFrame == 0)
            .accessibilityLabel(Text("이전 그림"))
            .accessibilityInputLabels([Text("이전"), Text("이전 그림")])
            .accessibilityShowsLargeContentViewer()

            // "다음 그림 그리기" — the main action, so it's big and colored:
            // a pencil with an arrow, meaning "now draw the next picture".
            Button { nextPage() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.outline")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: isCompact ? 22 : 26))
                .frame(width: isCompact ? 72 : 96, height: isCompact ? 44 : 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(project.currentFrame >= project.frameCount - 1)
            .accessibilityLabel(Text("다음 그림 그리기"))
            .accessibilityInputLabels([Text("다음"), Text("다음 그림 그리기")])
            .accessibilityShowsLargeContentViewer()
            .popoverTip(nextPageTip, arrowEdge: .bottom)

            Slider(value: Binding(
                get: { Double(project.currentFrame) },
                set: { project.goToFrame(Int($0)) }
            ), in: 0...Double(max(project.frameCount - 1, 1)))
            .accessibilityLabel(Text("장 넘기기"))
            .accessibilityValue(Text(verbatim: "\(project.currentFrame + 1) / \(project.frameCount)"))

            // Tuck the play bar away for a bigger canvas.
            Button {
                withAnimation { showTransport = false }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: isCompact ? 20 : 24, weight: .bold))
                    .frame(width: isCompact ? 36 : 56, height: isCompact ? 44 : 52)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("재생 막대 숨기기"))
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.vertical, isCompact ? 8 : 12)
    }

    private func nextPage() {
        nextPageTip.invalidate(reason: .actionPerformed)
        project.step(by: 1)
        Task { await DubTip.turnedPage.donate() }
    }

    // MARK: - Shortcuts (App Intents)

    /// Does what the Siri / Shortcuts action asked, the same way the home
    /// grid would — including the free-tier limit on saved works.
    private func handleShortcut(_ request: ShortcutRouter.Request) {
        shortcuts.pending = nil
        // Launched by the shortcut: don't let the launch restore reopen the
        // last work on top of the new one.
        restoredLastProject = true
        guard !project.isExporting, !project.isRecording else { return }
        switch request {
        case .newBlankFlipbook:
            showSupport = false
            if project.isOpen { project.goHome() }
            let saved = RotoProject.listProjects().count
            guard store.gate.evaluate(FreeTier.projectKey, current: saved).isAllowed else {
                lock = .projects
                return
            }
            project.createBlank()
        }
    }

    // MARK: - Export overlay (progress + big checkmark, no words)

    @ViewBuilder
    private var exportOverlay: some View {
        if project.isExporting {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 24) {
                    Image(systemName: "film")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                    ProgressView(value: project.exportProgress)
                        .frame(width: 280)
                        .scaleEffect(y: 2)
                        .tint(.green)
                }
            }
        } else if showDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 140))
                .foregroundStyle(.green)
                .shadow(radius: 8)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }

    // MARK: - Export

    private func runExport() {
        project.isExporting = true
        project.exportProgress = 0

        // One button, one result: an mp4 saved into Photos.
        let opts = Exporter.Options(writePNGSequence: false,
                                    writeProRes: false,
                                    saveToPhotos: true,
                                    endCard: !store.hasPro)
        let exporter = Exporter(project: project)

        Task {
            do {
                if project.isSketchbook {
                    // One page: a picture, not a movie.
                    try await exporter.savePicture()
                } else {
                    _ = try await exporter.export(options: opts) { p in
                        project.exportProgress = p
                    }
                }
                // A finished flipbook in Photos is what this app is for. The count
                // feeds "Enjoying Palang Book?", which is only ever asked in
                // Settings, after the grown-up check — never to the kid here.
                LeeoEngagement.shared.registerSignificantEvent()
                withAnimation(reduceMotion ? .easeOut : .bouncy) { showDone = true }
                // 큰 체크 표시가 보이지 않는 사람에게도 끝났다고 알린다.
                AccessibilityNotification.Announcement(String(localized: "사진 앱에 저장했어요")).post()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation { showDone = false }
            } catch {
                project.statusMessage = error.localizedDescription
            }
            project.isExporting = false
        }
    }
}

private extension View {
    /// One group of tools sits in its own soft tray.
    func toolTray() -> some View {
        HStack(spacing: Bar.gap) { self }
            .padding(Bar.gap)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.06)))
    }
}

/// One measure for the whole toolbar, so every tray and button lines up:
/// colors, stamps and size dots are one cell; a tool button on iPad is as
/// tall as two rows of cells, so every tray is the same height.
private enum Bar {
    static let gap: CGFloat = 6
    static func cell(_ compact: Bool) -> CGFloat { compact ? 34 : 36 }
    static func button(_ compact: Bool) -> CGFloat { compact ? cell(true) : cell(false) * 2 + gap }
}

/// A toolbar icon: one fixed size per device, so every button matches.
private struct ToolIcon: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .compact {
            content
                .font(.system(size: 20))
                .frame(width: 40, height: Bar.button(true))
        } else {
            content
                .font(.system(size: 28))
                .frame(width: 56, height: Bar.button(false))
        }
    }
}

/// Every toolbar button: a rounded block exactly its icon's size — no
/// system padding, so all buttons share one height.
private struct ToolStyle: ButtonStyle {
    var fill: Color
    var ink: Color = .white
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ink)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
