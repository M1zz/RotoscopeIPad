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
                        looksRow
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
            stampGrid.toolTray()
            HStack(spacing: 10) {
                colorPalette
                Divider().frame(height: 60)
                sizeDots
            }
            .toolTray()
            if !project.isSketchbook {
                moveTools.toolTray()
            }
            Spacer(minLength: 0)
            exportButton
        }
    }

    /// The colors stacked like a paint box, five over five, so one row holds everything.
    private var colorPalette: some View {
        let palette = RotoProject.palette
        let half = (palette.count + 1) / 2
        return Grid(horizontalSpacing: isCompact ? 14 : 8, verticalSpacing: 8) {
            GridRow { ForEach(palette.prefix(half), id: \.self) { colorDot($0) } }
            GridRow { ForEach(palette.dropFirst(half), id: \.self) { colorDot($0) } }
        }
    }

    /// Home on the left, save on the right, the trays in between.
    private var toolRow: some View {
        HStack(spacing: 12) {
            iconButton("house.fill", label: "홈으로") { project.goHome() }
            Spacer(minLength: 0)
            drawTools.toolTray()
            stampGrid.toolTray()
            if !project.isSketchbook {
                moveTools.toolTray()
            }
            Spacer(minLength: 0)
            exportButton
        }
    }

    /// Colors, then sizes: how the next line looks.
    private var looksRow: some View {
        HStack(spacing: 10) {
            ForEach(RotoProject.palette, id: \.self) { colorDot($0) }
            Divider().frame(height: 34)
            sizeDots
        }
        .toolTray()
    }

    /// A phone: home · draw tray · save, then stamps, then colors and sizes, then sound and play.
    @ViewBuilder
    private var compactRows: some View {
        HStack(spacing: 8) {
            iconButton("house.fill", label: "홈으로") { project.goHome() }
            drawTools.toolTray()
            exportButton
        }
        HStack(spacing: 0) {
            ForEach(StampShape.allCases) { stampButton($0).frame(maxWidth: .infinity) }
        }
        HStack(spacing: 12) {
            colorPalette
            Divider().frame(height: 50)
            sizeDots
        }
        if !project.isSketchbook {
            moveTools.toolTray()
        }
    }

    /// Draw and wipe: pen, stamp, eraser, and the whole-page trash.
    @ViewBuilder
    private var drawTools: some View {
        toolButton("paintbrush.pointed.fill", selected: project.tool == .brush, label: "붓") {
            project.tool = .brush
        }
        toolButton("eraser.fill", selected: project.tool == .erase, label: "지우개") {
            project.tool = .erase
        }
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

    /// Four over four, like the colors.
    private var stampGrid: some View {
        let shapes = StampShape.allCases
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow { ForEach(shapes.prefix(4)) { stampButton($0) } }
            GridRow { ForEach(shapes.dropFirst(4)) { stampButton($0) } }
        }
    }

    private func stampButton(_ shape: StampShape) -> some View {
        let selected = project.tool == .stamp && project.stampShape == shape
        return Button {
            project.stampShape = shape
            project.tool = .stamp
        } label: {
            StampGlyph(shape: shape, colorHex: project.brushColorHex)
                .frame(width: 24, height: 24)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor, lineWidth: selected ? 3 : 0)
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
                .frame(width: 36, height: 36)
        }
        .background(Circle().fill(selected ? Color.accentColor.opacity(0.25) : .clear))
        .accessibilityLabel(Self.stampSizeLabel(value))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var clearPageButton: some View {
        // Wipe the whole page — after the O / X question (no undo).
        Button { withAnimation(.snappy) { askClear = true } } label: {
            Image(systemName: "trash.fill")
                .modifier(ToolIcon())
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
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
        .buttonStyle(.borderedProminent)
        .tint(project.isRecording ? .red : (project.hasAudio ? .purple : .gray))
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
        .buttonStyle(.borderedProminent)
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
            .buttonStyle(.borderedProminent)
            .tint(project.hideBackground ? .pink : .gray)
            .accessibilityLabel(project.hideBackground
                                ? Text("동영상 배경 보이기") : Text("동영상 배경 숨기기"))
        }
    }

    private var exportButton: some View {
        Button { runExport() } label: {
            Image(systemName: "square.and.arrow.down.fill")
                .modifier(ToolIcon())
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
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
        .buttonStyle(.bordered)
        .accessibilityLabel(Text(label))
        .accessibilityShowsLargeContentViewer()
    }

    private func toolButton(_ symbol: String, selected: Bool, label: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        toolButton(selected: selected, label: label, action: action) { Image(systemName: symbol) }
    }

    private func toolButton<Icon: View>(selected: Bool, label: LocalizedStringKey,
                                        action: @escaping () -> Void,
                                        @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            icon()
                .modifier(ToolIcon())
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.2) : .clear)
        )
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
    }

    private func colorDot(_ hex: String) -> some View {
        let selected = project.brushColorHex == hex
            && (project.tool == .brush || project.tool == .stamp)
        return Circle()
            .fill(Color(rgbHex: hex))
            .frame(width: isCompact ? 26 : 36, height: isCompact ? 26 : 36)
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
        let selected = nearlyEqual(project.brushWidth, value)
        return Button { project.brushWidth = value } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: 8 + value * 500, height: 8 + value * 500)
                .frame(width: 36, height: 36)
        }
        .background(
            Circle().fill(selected ? Color.accentColor.opacity(0.25) : .clear)
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

extension StampShape {
    /// Spoken name for VoiceOver (the stamp buttons are icon-only).
    var accessibilityName: Text {
        switch self {
        case .heart:    return Text("하트 도장")
        case .circle:   return Text("동그라미 도장")
        case .square:   return Text("네모 도장")
        case .triangle: return Text("세모 도장")
        case .star:     return Text("별 도장")
        case .flower:   return Text("꽃 도장")
        case .car:      return Text("자동차 도장")
        case .bird:     return Text("새 도장")
        }
    }
}

/// A stamp drawn from its real outline in the pen color, so the button
/// shows exactly what lands on the page. A thin edge keeps white visible.
private struct StampGlyph: View {
    let shape: StampShape
    let colorHex: String

    var body: some View {
        Outline(shape: shape)
            .fill(Color(rgbHex: colorHex))
            .overlay(Outline(shape: shape).stroke(Color.primary.opacity(0.25), lineWidth: 1))
    }

    private struct Outline: Shape {
        let shape: StampShape

        func path(in rect: CGRect) -> Path {
            let r = min(rect.width, rect.height) / 2
            let points = shape.unitPoints.map {
                CGPoint(x: rect.midX + $0.x * r, y: rect.midY + $0.y * r)
            }
            return Path(StrokeGeometry.path(points: points, closed: true, smooth: shape.smooth))
        }
    }
}

private extension View {
    /// One group of tools sits in its own soft tray.
    func toolTray() -> some View {
        HStack(spacing: 8) { self }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.06)))
    }
}

/// A toolbar icon: big on iPad; on a phone the buttons in a row share its width.
private struct ToolIcon: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .compact {
            content
                .font(.system(size: 20))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        } else {
            content
                .font(.system(size: 26))
                .frame(width: 48, height: 48)
        }
    }
}
