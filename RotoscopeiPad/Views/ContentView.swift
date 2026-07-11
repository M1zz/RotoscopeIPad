import SwiftUI

/// Icon-only UI for pre-readers: no text anywhere.
/// One row of tools on top, the canvas, and play controls at the bottom.
struct ContentView: View {
    @EnvironmentObject var project: RotoProject
    @State private var showDone = false
    @State private var restoredLastProject = false
    @State private var showPageFlash = false
    @State private var pageFlashTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if project.isOpen {
                toolbar
                Divider()
                CanvasView()
                    .background(Color.black)
                Divider()
                transport
            } else {
                HomeView()
            }
        }
        .sheet(isPresented: $project.showPhotoPicker) {
            PhotosVideoPicker(isPresented: $project.showPhotoPicker,
                              onPick: { url in project.load(url: url) })
            .ignoresSafeArea()
        }
        .overlay { pageFlashOverlay }
        .overlay { exportOverlay }
        .onChange(of: project.currentFrame) { _ in
            guard project.isOpen, !project.isPlaying else { return }
            flashPageNumber()
        }
        .onAppear {
            // Come back right where you left off.
            guard !restoredLastProject else { return }
            restoredLastProject = true
            if let last = RotoProject.listProjects().first {
                project.openProject(at: last)
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
            Text("\(project.currentFrame + 1)\u{2009}/\u{2009}\(project.frameCount)")
                .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 36)
                .padding(.vertical, 20)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Toolbar (tools + colors + sizes + save)

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                iconButton("house.fill") { project.goHome() }

                Divider().frame(height: 34)

                toolButton("paintbrush.pointed.fill", tool: .brush)
                toolButton("eraser.fill", tool: .erase)
                iconButton("arrow.uturn.backward") { project.undoLastStroke() }

                Divider().frame(height: 34)

                // Dub: animation plays once while the mic records the kid.
                Button {
                    project.isRecording ? project.stopPlayback() : project.startDubbing()
                } label: {
                    Image(systemName: project.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 26))
                        .frame(width: 56, height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(project.isRecording ? .red : (project.hasAudio ? .purple : .gray))

                // Hide the video background: play/export only the drawing.
                if project.hasVideo {
                    Button { project.toggleHideBackground() } label: {
                        Image(systemName: project.hideBackground
                              ? "video.slash.fill" : "video.fill")
                            .font(.system(size: 26))
                            .frame(width: 56, height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(project.hideBackground ? .pink : .gray)
                }

                Divider().frame(height: 34)

                ForEach(RotoProject.palette, id: \.self) { hex in
                    colorDot(hex)
                }

                Divider().frame(height: 34)

                ForEach(RotoProject.widthPresets, id: \.name) { preset in
                    sizeDot(preset.value)
                }

                Divider().frame(height: 34)

                Button { runExport() } label: {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 26))
                        .frame(width: 56, height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(project.isExporting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .frame(width: 56, height: 48)
        }
        .buttonStyle(.bordered)
    }

    private func toolButton(_ symbol: String, tool: ToolMode) -> some View {
        Button { project.tool = tool } label: {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .frame(width: 56, height: 48)
        }
        .buttonStyle(.bordered)
        .tint(project.tool == tool ? .accentColor : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(project.tool == tool ? Color.accentColor.opacity(0.2) : .clear)
        )
    }

    private func colorDot(_ hex: String) -> some View {
        let selected = project.brushColorHex == hex && project.tool == .brush
        return Circle()
            .fill(Color(hex: hex))
            .frame(width: 36, height: 36)
            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
            .overlay(
                Circle().stroke(Color.accentColor, lineWidth: selected ? 4 : 0)
                    .padding(-4)
            )
            .onTapGesture {
                project.brushColorHex = hex
                project.tool = .brush   // picking a color always means "draw"
            }
    }

    private func sizeDot(_ value: Double) -> some View {
        let selected = nearlyEqual(project.brushWidth, value)
        return Button { project.brushWidth = value } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: 8 + value * 500, height: 8 + value * 500)
                .frame(width: 44, height: 44)
        }
        .background(
            Circle().fill(selected ? Color.accentColor.opacity(0.25) : .clear)
        )
    }

    private func nearlyEqual(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0005 }

    // MARK: - Transport (frame navigation + play)

    private var transport: some View {
        HStack(spacing: 18) {
            // "이전 그림" — mirrors the next button, quieter color.
            Button { project.step(by: -1) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                    Image(systemName: "photo")
                }
                .font(.system(size: 24))
                .frame(width: 88, height: 52)
            }
            .buttonStyle(.bordered)
            .disabled(project.currentFrame == 0)

            Button { project.togglePlayback() } label: {
                Image(systemName: project.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30))
                    .frame(width: 68, height: 52)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.space, modifiers: [])

            // "다음 그림 그리기" — the main action, so it's big and colored:
            // a pencil with an arrow, meaning "now draw the next picture".
            Button { project.step(by: 1) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.outline")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 26))
                .frame(width: 96, height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!project.isBlank && project.currentFrame >= project.frameCount - 1)

            Slider(value: Binding(
                get: { Double(project.currentFrame) },
                set: { project.goToFrame(Int($0)) }
            ), in: 0...Double(max(project.frameCount - 1, 1)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Export

    private func runExport() {
        project.isExporting = true
        project.exportProgress = 0

        // One button, one result: an mp4 saved into Photos.
        let opts = Exporter.Options(writePNGSequence: false,
                                    writeProRes: false,
                                    saveToPhotos: true)
        let exporter = Exporter(project: project)

        Task {
            do {
                _ = try await exporter.export(options: opts) { p in
                    project.exportProgress = p
                }
                withAnimation(.bouncy) { showDone = true }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation { showDone = false }
            } catch {
                project.statusMessage = error.localizedDescription
            }
            project.isExporting = false
        }
    }
}
