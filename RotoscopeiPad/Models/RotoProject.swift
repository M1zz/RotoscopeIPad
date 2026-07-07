import SwiftUI
import AVFoundation
import UIKit

/// Drawing tool modes. Raw values are the kid-facing Korean labels.
enum ToolMode: String, CaseIterable {
    case polygon = "도형"
    case brush   = "붓"
    case erase   = "지우개"
}

/// How the export bakes strokes into each frame.
enum RenderMode: String, CaseIterable {
    case paint  = "그림 얹기"     // colored strokes drawn over the frame (animation)
    case cutout = "배경 없애기"   // strokes define an alpha mask, background removed
}

@MainActor
final class RotoProject: ObservableObject {
    @Published var source: VideoSource?
    @Published var videoURL: URL?
    @Published var currentFrame: Int = 0
    @Published var displayImage: UIImage?

    @Published var masks: [Int: FrameMask] = [:]
    @Published var tool: ToolMode = .brush
    /// Flipbook feel: the previous drawing shows through faintly so the kid
    /// thinks "이제 다음 그림을 그린다", not "next video frame".
    @Published var showOnionSkin: Bool = true
    @Published var maskOpacity: Double = 0.45

    // MARK: - Brush / palette

    /// Kid palette: a few bright, clearly different colors.
    static let palette: [String] = [
        "FF3B30", "FF9500", "FFCC00", "34C759", "00C7BE",
        "007AFF", "AF52DE", "FF2D55", "FFFFFF", "000000"
    ]

    /// Three brush sizes: small, medium, big.
    static let widthPresets: [(name: String, value: Double)] = [
        ("S", 0.008), ("M", 0.016), ("L", 0.034)
    ]

    @Published var brushColorHex: String = "000000"
    @Published var brushWidth: Double = 0.016
    @Published var brushOpacity: Double = 1.0
    @Published var brushSmoothing: Bool = true

    /// What the export bakes into each frame. Paint = colored drawing over the
    /// footage; Cutout = the original alpha matte behavior.
    @Published var renderMode: RenderMode = .paint

    /// When true, drawing requires an Apple Pencil (palm rejection while
    /// the finger pans/zooms). Off by default so finger drawing works too.
    @Published var pencilOnly: Bool = false

    @Published var liveStroke: MaskStroke?

    // MARK: - Playback

    @Published var isPlaying = false
    private var playbackTask: Task<Void, Never>?

    // MARK: - Voice dubbing (아이 목소리 녹음)

    @Published var isRecording = false
    private var recorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?

    /// The project's narration track.
    var audioURL: URL? { projectDirectory?.appendingPathComponent("audio.m4a") }
    var hasAudio: Bool {
        guard let url = audioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Records the mic while the animation plays through once, so the kid
    /// dubs along with their own pictures. Re-recording overwrites.
    func startDubbing() {
        guard isOpen, frameCount > 1, !isRecording, let audioURL else { return }
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard granted, let self else { return }
                self.beginDubbing(to: audioURL)
            }
        }
    }

    private func beginDubbing(to url: URL) {
        // Rewind first: goToFrame stops playback, which would end the take
        // if the recorder were already running.
        stopPlayback()
        goToFrame(0)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
        try? session.setActive(true)

        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else { return }
        recorder = rec
        rec.record()
        isRecording = true
        startPlayback(loop: false)   // one pass; stopping playback ends the take
    }

    private func stopDubbing() {
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        scheduleSave()
    }

    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var statusMessage: String = "동영상을 가져오면 시작할 수 있어요!"

    // Sheet / picker triggers for the UI.
    @Published var showVideoPicker = false
    @Published var showPhotoPicker = false
    @Published var showCameraPicker = false
    @Published var exportedFolderURL: URL?
    @Published var showExportDoneSheet = false

    // MARK: - Scene sampling
    // Drawing every video frame is way too much for a kid — sample the video
    // down to ~8 drawings per second ("shooting on threes/fours").

    static let targetSceneFPS: Double = 8

    /// How many video frames one drawn scene covers (1 = every frame).
    @Published private(set) var frameStep: Int = 1

    // MARK: - Blank flipbook projects (no video, just pages)

    static let blankCanvasSize = CGSize(width: 1600, height: 1200)
    static let blankFPS: Double = 8
    static let maxBlankPages = 600

    @Published var isBlank = false
    @Published var blankPageCount = 1

    /// Drawing surface size: the video frame, or the blank page.
    var canvasSize: CGSize { source?.naturalSize ?? Self.blankCanvasSize }

    /// Number of drawable scenes (sampled frames or blank pages).
    var frameCount: Int {
        if isBlank { return blankPageCount }
        guard let src = source else { return 0 }
        return (src.frameCount + frameStep - 1) / frameStep
    }

    /// Maps a scene index to its underlying video frame.
    func videoFrame(forScene i: Int) -> Int {
        guard let src = source else { return i }
        return min(i * frameStep, src.frameCount - 1)
    }

    var hasVideo: Bool { source != nil }

    /// True while any project (video or blank) is open in the editor.
    var isOpen: Bool { source != nil || (isBlank && projectDirectory != nil) }

    // MARK: - Project storage
    // Each project lives in Documents/Projects/<uuid>/ with the video file,
    // project.json (masks + position) and thumb.png for the home grid.

    @Published var projectDirectory: URL?
    private var saveTask: Task<Void, Never>?

    private struct ProjectData: Codable {
        var frameStep: Int
        var currentFrame: Int
        var masks: [Int: FrameMask]
        var videoFileName: String?
        var isBlank: Bool
        var blankPageCount: Int

        init(frameStep: Int, currentFrame: Int, masks: [Int: FrameMask],
             videoFileName: String?, isBlank: Bool, blankPageCount: Int) {
            self.frameStep = frameStep
            self.currentFrame = currentFrame
            self.masks = masks
            self.videoFileName = videoFileName
            self.isBlank = isBlank
            self.blankPageCount = blankPageCount
        }

        // Defaults keep projects saved before blank support loading fine.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            frameStep = try c.decodeIfPresent(Int.self, forKey: .frameStep) ?? 1
            currentFrame = try c.decodeIfPresent(Int.self, forKey: .currentFrame) ?? 0
            masks = try c.decodeIfPresent([Int: FrameMask].self, forKey: .masks) ?? [:]
            videoFileName = try c.decodeIfPresent(String.self, forKey: .videoFileName)
            isBlank = try c.decodeIfPresent(Bool.self, forKey: .isBlank) ?? false
            blankPageCount = try c.decodeIfPresent(Int.self, forKey: .blankPageCount) ?? 1
        }
    }

    static var projectsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
    }

    /// Project folders, most recently edited first.
    static func listProjects() -> [URL] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: projectsRoot,
                                                     includingPropertiesForKeys: nil) else { return [] }
        func editedAt(_ dir: URL) -> Date {
            let json = dir.appendingPathComponent("project.json")
            return (try? fm.attributesOfItem(atPath: json.path)[.modificationDate] as? Date)
                .flatMap { $0 } ?? .distantPast
        }
        return dirs.filter { $0.hasDirectoryPath }
            .sorted { editedAt($0) > editedAt($1) }
    }

    /// Deletes a project folder (video, drawings, thumbnail).
    static func deleteProject(at dir: URL) {
        // Only ever remove folders that live under our Projects root.
        guard dir.resolvingSymlinksInPath().path
            .hasPrefix(projectsRoot.resolvingSymlinksInPath().path) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Create / open / close

    /// Creates a new project from a picked video.
    func load(url: URL) {
        stopPlayback()
        // Security-scoped access for files coming from the document picker.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let dir = Self.projectsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
        let dest = dir.appendingPathComponent("video.\(ext)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            statusMessage = "동영상을 가져오지 못했어요: \(error.localizedDescription)"
            return
        }

        guard let src = VideoSource(url: dest) else {
            statusMessage = "동영상을 읽을 수 없어요. 다른 동영상으로 해볼까요?"
            try? FileManager.default.removeItem(at: dir)
            return
        }
        source = src
        videoURL = dest
        projectDirectory = dir
        isBlank = false
        blankPageCount = 1
        frameStep = max(1, Int((Double(src.frameRate) / Self.targetSceneFPS).rounded()))
        masks = [:]
        currentFrame = 0
        statusMessage = "준비 완료! 장면이 \(frameCount)개 있어요. 그림을 그려보세요 🎨"
        refreshFrame()
        saveNow()
        writeThumbnail()
    }

    /// Creates a blank flipbook project: white pages, no video. New pages are
    /// added by tapping "next" on the last page.
    func createBlank() {
        stopPlayback()
        let dir = Self.projectsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch { return }
        source = nil
        videoURL = nil
        displayImage = nil
        projectDirectory = dir
        isBlank = true
        blankPageCount = 1
        frameStep = 1
        masks = [:]
        currentFrame = 0
        liveStroke = nil
        saveNow()
        writeThumbnail()
    }

    /// Reopens a saved project folder.
    func openProject(at dir: URL) {
        stopPlayback()
        guard let json = try? Data(contentsOf: dir.appendingPathComponent("project.json")),
              let data = try? JSONDecoder().decode(ProjectData.self, from: json) else { return }

        if data.isBlank {
            source = nil
            videoURL = nil
            displayImage = nil
            isBlank = true
            blankPageCount = max(1, data.blankPageCount)
        } else {
            guard let name = data.videoFileName else { return }
            let vurl = dir.appendingPathComponent(name)
            guard let src = VideoSource(url: vurl) else { return }
            source = src
            videoURL = vurl
            isBlank = false
            blankPageCount = 1
        }
        projectDirectory = dir
        frameStep = max(1, data.frameStep)
        masks = data.masks
        currentFrame = min(max(0, data.currentFrame), frameCount - 1)
        liveStroke = nil
        refreshFrame()
    }

    /// Saves and returns to the home grid.
    func goHome() {
        stopPlayback()
        saveNow()
        writeThumbnail()
        source = nil
        displayImage = nil
        videoURL = nil
        projectDirectory = nil
        isBlank = false
        blankPageCount = 1
        masks = [:]
        liveStroke = nil
        currentFrame = 0
    }

    // MARK: - Autosave

    /// Debounced save: strokes come fast while drawing.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        guard let dir = projectDirectory else { return }
        let data = ProjectData(frameStep: frameStep, currentFrame: currentFrame,
                               masks: masks, videoFileName: videoURL?.lastPathComponent,
                               isBlank: isBlank, blankPageCount: blankPageCount)
        if let json = try? JSONEncoder().encode(data) {
            try? json.write(to: dir.appendingPathComponent("project.json"), options: .atomic)
        }
    }

    /// Home-grid thumbnail: the current frame (or white page) with its drawing.
    private func writeThumbnail() {
        guard let dir = projectDirectory else { return }
        let base = displayImage
        let srcSize = base?.size ?? canvasSize
        let scale = min(1, 480 / max(srcSize.width, 1))
        let size = CGSize(width: srcSize.width * scale, height: srcSize.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let data = renderer.pngData { rc in
            if let base {
                base.draw(in: CGRect(origin: .zero, size: size))
            } else {
                UIColor.white.setFill()
                rc.fill(CGRect(origin: .zero, size: size))
            }
            if let paint = MaskRasterizer.paintLayer(for: currentMask, size: size) {
                UIImage(cgImage: paint).draw(in: CGRect(origin: .zero, size: size))
            }
        }
        try? data.write(to: dir.appendingPathComponent("thumb.png"))
    }

    // MARK: - Playback

    func togglePlayback() {
        isPlaying ? stopPlayback() : startPlayback()
    }

    /// Plays the video with the drawn strokes overlaid, looping. Frames are
    /// paced by the wall clock so slow decodes drop frames instead of
    /// stretching time.
    func startPlayback(loop: Bool = true) {
        guard isOpen, frameCount > 1, !isPlaying else { return }
        isPlaying = true
        liveStroke = nil
        let startFrame = currentFrame >= frameCount - 1 ? 0 : currentFrame
        // Scenes advance at the sampled rate, matching the exported result.
        let src = source
        let sceneFPS = src.map { Double($0.frameRate) / Double(frameStep) } ?? Self.blankFPS
        let clockStart = Date()

        // Recorded narration plays along (but not while re-recording it).
        if !isRecording, hasAudio, let audioURL,
           let player = try? AVAudioPlayer(contentsOf: audioURL) {
            audioPlayer = player
            player.currentTime = Double(startFrame) / sceneFPS
            player.play()
        }

        playbackTask = Task { [weak self] in
            while let self, self.isPlaying, !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(clockStart)
                let rawTarget = startFrame + Int(elapsed * sceneFPS)
                if !loop && rawTarget >= self.frameCount {
                    self.stopPlayback()   // single pass done (ends a dubbing take)
                    break
                }
                let target = rawTarget % self.frameCount
                if target != self.currentFrame {
                    // Loop wrapped: restart narration from the top.
                    if target < self.currentFrame, let player = self.audioPlayer {
                        player.currentTime = 0
                        player.play()
                    }
                    if let src {
                        let videoFrame = self.videoFrame(forScene: target)
                        // Decode off the main actor so the UI stays responsive.
                        let img = await Task.detached(priority: .userInitiated) {
                            src.previewImage(atFrame: videoFrame)
                        }.value
                        guard self.isPlaying else { break }
                        if let img { self.displayImage = img }
                    }
                    self.currentFrame = target
                }
                try? await Task.sleep(nanoseconds: UInt64(500_000_000 / sceneFPS))
            }
        }
    }

    func stopPlayback() {
        stopDubbing()
        audioPlayer?.stop()
        audioPlayer = nil
        guard isPlaying else { return }
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
        refreshFrame()   // swap back to the full-resolution still
    }

    // MARK: - Navigation

    func step(by delta: Int) {
        guard isOpen else { return }
        stopPlayback()
        // Blank flipbook: stepping forward past the last page adds a new one.
        if isBlank, delta > 0, currentFrame == frameCount - 1,
           blankPageCount < Self.maxBlankPages {
            blankPageCount += 1
        }
        let next = min(max(currentFrame + delta, 0), frameCount - 1)
        if next != currentFrame {
            currentFrame = next
            liveStroke = nil
            refreshFrame()
            scheduleSave()
        }
    }

    func goToFrame(_ i: Int) {
        guard isOpen else { return }
        stopPlayback()
        currentFrame = min(max(i, 0), frameCount - 1)
        liveStroke = nil
        refreshFrame()
        scheduleSave()
    }

    private func refreshFrame() {
        guard let src = source else {
            displayImage = nil   // blank project: white page drawn by the canvas
            return
        }
        displayImage = src.uiImage(atFrame: videoFrame(forScene: currentFrame))
    }

    // MARK: - Mask access

    var currentMask: FrameMask { masks[currentFrame] ?? FrameMask() }

    func commitStroke(_ stroke: MaskStroke) {
        var m = masks[currentFrame] ?? FrameMask()
        m.strokes.append(stroke)
        masks[currentFrame] = m
        liveStroke = nil
        scheduleSave()
        writeThumbnail()
    }

    func clearCurrentMask() {
        masks[currentFrame] = FrameMask()
        scheduleSave()
    }

    func copyMaskFromPrevious() {
        guard currentFrame > 0, let prev = masks[currentFrame - 1] else { return }
        masks[currentFrame] = prev
        scheduleSave()
    }

    func undoLastStroke() {
        guard var m = masks[currentFrame], !m.strokes.isEmpty else { return }
        m.strokes.removeLast()
        masks[currentFrame] = m
        scheduleSave()
    }
}
