import SwiftUI
import AVFoundation
import UIKit

/// Drawing tool modes. Raw values are the kid-facing Korean labels.
enum ToolMode: String, CaseIterable {
    case polygon = "도형"
    case brush   = "붓"
    case erase   = "지우개"
    case stamp   = "도장"
    case move    = "옮기기"
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
    @Published var tool: ToolMode = .brush {
        didSet { if oldValue != tool { previousTool = oldValue } }
    }
    /// 바로 전에 쓰던 도구 — Apple Pencil 두 번 탭으로 오간다.
    private(set) var previousTool: ToolMode = .brush

    /// Apple Pencil 두 번 탭. 설정 ▸ Apple Pencil 에서 고른 동작을 따른다:
    /// 지우개로 바꾸기면 지우개 ↔ 쓰던 도구, 이전 도구로 바꾸기면 바로 전 도구로.
    func pencilDoubleTap(switchToPrevious: Bool) {
        guard !isPlaying else { return }
        if switchToPrevious {
            tool = previousTool
        } else if tool == .erase {
            tool = previousTool == .erase ? .brush : previousTool
        } else {
            tool = .erase
        }
    }
    /// Flipbook feel: the previous drawing shows through faintly so the kid
    /// thinks "이제 다음 그림을 그린다", not "next video frame".
    @Published var showOnionSkin: Bool = true
    @Published var maskOpacity: Double = 0.45

    // MARK: - Brush / palette

    /// Kid palette: the rainbow in order (빨주노초파남보), then pink, white, black.
    static let palette: [String] = [
        "FF3B30", "FF9500", "FFCC00", "34C759", "007AFF",
        "3A3FBF", "AF52DE", "FF2D55", "FFFFFF", "000000"
    ]

    /// Three brush sizes: small, medium, big.
    static let widthPresets: [(name: String, value: Double)] = [
        ("S", 0.008), ("M", 0.016), ("L", 0.034)
    ]

    @Published var brushColorHex: String = "000000"
    @Published var brushWidth: Double = 0.016
    @Published var brushOpacity: Double = 1.0
    @Published var brushSmoothing: Bool = true

    // MARK: - Stamps (도장)

    @Published var stampShape: StampShape = .heart

    /// Stamp width as a fraction of the canvas width, with its own S/M/L
    /// dots in the stamp column (independent of the brush size).
    @Published var stampSize: Double = 0.16
    static let stampSizePresets: [Double] = [0.09, 0.16, 0.28]

    /// Where a stamp centered at `p` would land, in normalized coordinates.
    /// Shared by the actual stamp and the hover preview so they always match.
    func stampParts(centeredAt p: CGPoint) -> [StampPart] {
        // y is normalized by height, x by width — scale y by the aspect
        // ratio so stamps stay square on screen.
        let aspect = canvasSize.width / max(canvasSize.height, 1)
        let halfX = CGFloat(stampSize) / 2
        let halfY = halfX * aspect
        func clamped(_ v: CGFloat, margin: CGFloat) -> CGFloat {
            margin >= 0.5 ? 0.5 : min(max(v, margin), 1 - margin)
        }
        let cx = clamped(p.x, margin: halfX)
        let cy = clamped(p.y, margin: halfY)
        return stampShape.parts.map { part in
            StampPart(points: part.points.map { CGPoint(x: cx + $0.x * halfX, y: cy + $0.y * halfY) },
                      smooth: part.smooth)
        }
    }

    /// Stamps the selected shape at a normalized canvas point, as regular
    /// closed strokes in the current color (so erase/export just work).
    func stamp(at p: CGPoint) {
        guard isOpen, !isPlaying else { return }
        let group = UUID()
        for part in stampParts(centeredAt: p) {
            var piece = MaskStroke(points: part.points,
                                   isAdditive: true, closed: true,
                                   colorHex: brushColorHex, width: 0.004,
                                   opacity: brushOpacity, smooth: part.smooth)
            piece.group = group
            commitStroke(piece)
        }
        // One tap, one stamp, then back to the pen — kids couldn't find
        // their way out of stamping.
        tool = .brush
    }

    // MARK: - The hand: move a shape
    // Shapes (stamps and closed polygons) can be picked up and slid around
    // the page; lines stay where they were drawn.

    /// The strokes under the hand and where the finger was last.
    private var grabbed: (ids: Set<UUID>, last: CGPoint)?

    /// Picks up the topmost shape under `p`, with all of its stamp pieces.
    func grabShape(at p: CGPoint) {
        guard let strokes = masks[currentFrame]?.strokes,
              let hit = strokes.last(where: { $0.isAdditive && $0.closed && Self.contains($0.points, p) })
        else { return }
        let ids = strokes.filter { $0.id == hit.id || (hit.group != nil && $0.group == hit.group) }.map(\.id)
        grabbed = (Set(ids), p)
    }

    /// Slides the picked-up shape with the finger, never off the page.
    func dragShape(to p: CGPoint) {
        guard let g = grabbed, var m = masks[currentFrame] else { return }
        let points = m.strokes.filter { g.ids.contains($0.id) }.flatMap(\.points)
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return }
        let dx = min(max(p.x - g.last.x, -minX), 1 - maxX)
        let dy = min(max(p.y - g.last.y, -minY), 1 - maxY)
        for i in m.strokes.indices where g.ids.contains(m.strokes[i].id) {
            m.strokes[i].points = m.strokes[i].points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        }
        masks[currentFrame] = m
        grabbed?.last = CGPoint(x: g.last.x + dx, y: g.last.y + dy)
    }

    func dropShape() {
        guard grabbed != nil else { return }
        grabbed = nil
        scheduleSave()
        writeThumbnail()
    }

    /// Even-odd point-in-polygon test in normalized space.
    private static func contains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: - Hover preview
    // Pencil hover (or a trackpad pointer) shows where the next stroke or
    // stamp will land before it touches the page.

    @Published var hoverPoint: CGPoint?
    /// A stamp held under the finger: it appears on touch, follows the
    /// drag, and lands where the finger lifts.
    @Published var heldStamp: CGPoint?

    /// What the export bakes into each frame. Paint = colored drawing over the
    /// footage; Cutout = the original alpha matte behavior.
    @Published var renderMode: RenderMode = .paint

    /// Hide the video background: playback and export show only the kid's
    /// drawings on a white page. The video was just the tracing guide —
    /// same idea as the bundled presets, but with the kid's own footage.
    @Published var hideBackground = false

    func toggleHideBackground() {
        hideBackground.toggle()
        scheduleSave()
    }

    /// When true, drawing requires an Apple Pencil (palm rejection while
    /// the finger pans/zooms). Off by default so finger drawing works too.
    @Published var pencilOnly: Bool = false

    @Published var liveStroke: MaskStroke?

    // MARK: - Playback

    @Published var isPlaying = false
    private var playbackTask: Task<Void, Never>?

    // MARK: - Voice dubbing (아이 목소리 녹음)

    @Published var isRecording = false
    /// Set when a free take hits its time limit, so the UI can offer the unlock.
    @Published var recordingLimitReached = false
    private var recorder: AVAudioRecorder?
    private var recordingLimitTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?

    /// The project's narration track.
    var audioURL: URL? { projectDirectory?.appendingPathComponent("audio.m4a") }
    var hasAudio: Bool {
        guard let url = audioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Records the mic while the animation loops, so the kid dubs along with
    /// their own pictures for as long as they like; pressing stop ends the
    /// take. Re-recording overwrites. A `limit` (free tier) ends the take
    /// after that many seconds.
    func startDubbing(limit: TimeInterval? = nil) {
        guard isOpen, frameCount > 1, !isRecording, let audioURL else { return }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard granted, let self else { return }
                self.beginDubbing(to: audioURL, limit: limit)
            }
        }
    }

    private func beginDubbing(to url: URL, limit: TimeInterval?) {
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
        startPlayback()   // loops until the kid presses stop, ending the take

        if let limit {
            recordingLimitTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
                guard !Task.isCancelled, let self, self.isRecording else { return }
                self.stopPlayback()   // keeps the take recorded so far
                self.recordingLimitReached = true
            }
        }
    }

    private func stopDubbing() {
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        scheduleSave()
    }

    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var statusMessage: String = String(localized: "동영상을 가져오면 시작할 수 있어요!")

    // Sheet / picker triggers for the UI.
    @Published var showVideoPicker = false
    @Published var showPhotoPicker = false
    @Published var showCameraPicker = false
    @Published var showLinkImport = false
    @Published var exportedFolderURL: URL?
    @Published var showExportDoneSheet = false

    // MARK: - Scene sampling
    // Drawing every video frame is way too much for a kid — sample the video
    // down to ~8 drawings per second ("shooting on threes/fours").

    static let targetSceneFPS: Double = 8

    /// How many video frames one drawn scene covers (1 = every frame).
    @Published private(set) var frameStep: Int = 1

    // MARK: - Blank projects (no video): a one-page sketchbook

    nonisolated static let blankCanvasSize = CGSize(width: 1600, height: 1200)
    static let blankFPS: Double = 8

    @Published var isBlank = false
    @Published var blankPageCount = 1
    /// A sketchbook page takes the shape of the screen it's drawn on, so it
    /// fills the editor; it follows the screen until the first line lands.
    /// Older blank works with drawings stay 4:3.
    @Published private(set) var pageSize: CGSize?

    // MARK: - A grown-up's picture under the page
    // A sketchbook can start from a picture a grown-up brought in
    // (PictureLibrary). It sits on the page, faded or not, and the kid
    // draws over it; the saved picture keeps it.

    static let pictureFileName = "picture.jpg"
    @Published private(set) var picture: UIImage?
    @Published private(set) var pictureFaded = false
    var pictureOpacity: Double { pictureFaded ? PictureLibrary.fadedOpacity : 1 }

    // MARK: - Guide presets (따라 그리기)
    // A bundled sequence of light line-art pages. The kid traces each page;
    // playback and export hide the guides, so only the drawing animates.

    @Published private(set) var presetId: String?
    /// The current page's guide, shown faintly under the kid's strokes.
    @Published var guideImage: UIImage?
    private var guidePreset: GuidePreset?

    var isPreset: Bool { presetId != nil }
    /// 빈 종이: a single-page sketchbook — no page turning, playing or voice.
    /// (Blank works from before it became a sketchbook keep their pages.)
    var isSketchbook: Bool { isBlank && blankPageCount == 1 }

    /// Drawing surface size: the video frame, the guide page, or the blank page.
    var canvasSize: CGSize {
        source?.naturalSize ?? guidePreset?.canvasSize ?? pageSize ?? Self.blankCanvasSize
    }

    /// Shapes a sketchbook's page to the drawing area (long side 1600) while
    /// it's still empty — once drawn on, its shape never changes.
    func fitPage(to area: CGSize) {
        guard isSketchbook, picture == nil, area.width > 1, area.height > 1,
              masks.values.allSatisfy(\.strokes.isEmpty) else { return }
        let scale = Self.blankCanvasSize.width / max(area.width, area.height)
        let size = CGSize(width: (area.width * scale).rounded(), height: (area.height * scale).rounded())
        guard size != pageSize else { return }
        pageSize = size
        saveNow()
    }

    /// Number of drawable scenes (sampled frames, guide pages or blank pages).
    var frameCount: Int {
        if let guidePreset { return guidePreset.frameURLs.count }
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

    /// True while any project (video, preset or blank) is open in the editor.
    var isOpen: Bool {
        source != nil || ((isBlank || isPreset) && projectDirectory != nil)
    }

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
        var presetId: String?
        var hideBackground: Bool
        var pageSize: CGSize?
        var pictureFaded: Bool?

        init(frameStep: Int, currentFrame: Int, masks: [Int: FrameMask],
             videoFileName: String?, isBlank: Bool, blankPageCount: Int,
             presetId: String?, hideBackground: Bool, pageSize: CGSize?,
             pictureFaded: Bool? = nil) {
            self.pictureFaded = pictureFaded
            self.frameStep = frameStep
            self.currentFrame = currentFrame
            self.masks = masks
            self.videoFileName = videoFileName
            self.isBlank = isBlank
            self.blankPageCount = blankPageCount
            self.presetId = presetId
            self.hideBackground = hideBackground
            self.pageSize = pageSize
        }

        // Defaults keep projects saved before blank/preset support loading fine.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            frameStep = try c.decodeIfPresent(Int.self, forKey: .frameStep) ?? 1
            currentFrame = try c.decodeIfPresent(Int.self, forKey: .currentFrame) ?? 0
            masks = try c.decodeIfPresent([Int: FrameMask].self, forKey: .masks) ?? [:]
            videoFileName = try c.decodeIfPresent(String.self, forKey: .videoFileName)
            isBlank = try c.decodeIfPresent(Bool.self, forKey: .isBlank) ?? false
            blankPageCount = try c.decodeIfPresent(Int.self, forKey: .blankPageCount) ?? 1
            presetId = try c.decodeIfPresent(String.self, forKey: .presetId)
            hideBackground = try c.decodeIfPresent(Bool.self, forKey: .hideBackground) ?? false
            pageSize = try c.decodeIfPresent(CGSize.self, forKey: .pageSize)
            pictureFaded = try c.decodeIfPresent(Bool.self, forKey: .pictureFaded)
        }
    }

    static var projectsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
    }

    /// Project folders, most recently edited first.
    static func listProjects() -> [URL] { listWorks(in: projectsRoot) }

    /// Work folders under a root (the shelf or the trash), most recently edited first.
    private static func listWorks(in root: URL) -> [URL] {
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: root,
                                                                      includingPropertiesForKeys: nil) else { return [] }
        // Read each date once, not on every comparison — the shelf can hold dozens of works.
        let dated: [(dir: URL, at: Date)] = dirs.filter(\.hasDirectoryPath)
            .map { ($0, editedAt($0) ?? .distantPast) }
        return dated.sorted { $0.at > $1.at }.map(\.dir)
    }

    /// When a work was last drawn on (its project.json was saved).
    static func editedAt(_ dir: URL) -> Date? {
        let json = dir.appendingPathComponent("project.json")
        return (try? FileManager.default.attributesOfItem(atPath: json.path)[.modificationDate]) as? Date
    }

    /// Posted after works are deleted, so the home grid redraws behind the settings sheet.
    static let projectsDidChange = Notification.Name("RotoProject.projectsDidChange")

    // MARK: - Trash (휴지통)
    // Nothing a kid throws away is gone for good: a page wiped with the trash
    // button and a work deleted from the shelf wait here, behind the grown-up
    // check, until a grown-up brings them back or deletes them for good.

    static var trashRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Trash", isDirectory: true)
    }

    /// Works in the trash, most recently edited first.
    static func listTrash() -> [URL] { listWorks(in: trashRoot) }

    /// Shelf → trash.
    static func moveToTrash(_ dirs: some Sequence<URL>) {
        move(dirs, from: projectsRoot, to: trashRoot)
    }

    /// Trash → shelf: back on the home grid.
    static func restoreFromTrash(_ dirs: some Sequence<URL>) {
        move(dirs, from: trashRoot, to: projectsRoot)
    }

    /// Deletes works in the trash for good (video, drawings, thumbnail).
    static func deleteFromTrash(_ dirs: some Sequence<URL>) {
        let root = trashRoot.resolvingSymlinksInPath().path
        for dir in dirs {
            // Only ever remove folders that live in the trash.
            guard dir.resolvingSymlinksInPath().path.hasPrefix(root) else { continue }
            try? FileManager.default.removeItem(at: dir)
            thumbnails.removeObject(forKey: dir as NSURL)
        }
        NotificationCenter.default.post(name: projectsDidChange, object: nil)
    }

    private static func move(_ dirs: some Sequence<URL>, from source: URL, to target: URL) {
        let root = source.resolvingSymlinksInPath().path
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for dir in dirs where dir.resolvingSymlinksInPath().path.hasPrefix(root) {
            try? FileManager.default.moveItem(at: dir, to: target.appendingPathComponent(dir.lastPathComponent))
            thumbnails.removeObject(forKey: dir as NSURL)
        }
        NotificationCenter.default.post(name: projectsDidChange, object: nil)
    }

    /// A wiped page goes to the trash as a one-page sketchbook of its own.
    private func keepInTrash(_ mask: FrameMask) {
        let dir = Self.trashRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil
        else { return }
        let data = ProjectData(frameStep: 1, currentFrame: 0, masks: [0: mask], videoFileName: nil,
                               isBlank: true, blankPageCount: 1, presetId: nil,
                               hideBackground: false, pageSize: canvasSize,
                               pictureFaded: picture == nil ? nil : pictureFaded)
        if let json = try? JSONEncoder().encode(data) {
            try? json.write(to: dir.appendingPathComponent("project.json"), options: .atomic)
        }
        // The picture under the page goes along, so it comes back whole.
        if let work = projectDirectory, picture != nil {
            try? FileManager.default.copyItem(at: work.appendingPathComponent(Self.pictureFileName),
                                              to: dir.appendingPathComponent(Self.pictureFileName))
        }
        Self.writeThumbnail(to: dir, base: nil, guide: picture, guideAlpha: pictureOpacity,
                            mask: mask, canvasSize: canvasSize)
    }

    // MARK: - Thumbnails

    /// Decoded home-grid pictures. The grid redraws often and a busy shelf has
    /// dozens of works; decoding every PNG on each redraw made scrolling stutter.
    private static let thumbnails = NSCache<NSURL, UIImage>()

    /// A work's thumbnail, decoded once and kept until the work changes.
    static func thumbnail(for dir: URL) -> UIImage? {
        if let hit = thumbnails.object(forKey: dir as NSURL) { return hit }
        guard let image = UIImage(contentsOfFile: dir.appendingPathComponent("thumb.png").path)?
            .preparingForDisplay() else { return nil }
        thumbnails.setObject(image, forKey: dir as NSURL)
        return image
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
            statusMessage = String(localized: "동영상을 가져오지 못했어요: \(error.localizedDescription)")
            return
        }

        Task { await start(videoAt: dest, in: dir) }
    }

    /// Second half of `load(url:)`: the copy is in place, read it and begin.
    private func start(videoAt dest: URL, in dir: URL) async {
        guard let src = await VideoSource.load(url: dest) else {
            statusMessage = String(localized: "동영상을 읽을 수 없어요. 다른 동영상으로 해볼까요?")
            try? FileManager.default.removeItem(at: dir)
            return
        }
        FreeTier.recordVideoImport()
        source = src
        videoURL = dest
        projectDirectory = dir
        isBlank = false
        blankPageCount = 1
        clearPreset()
        hideBackground = false
        frameStep = max(1, Int((Double(src.frameRate) / Self.targetSceneFPS).rounded()))
        masks = [:]
        currentFrame = 0
        statusMessage = String(localized: "준비 완료! 장면이 \(frameCount)개 있어요. 그림을 그려보세요 🎨")
        refreshFrame()
        saveNow()
        writeThumbnail()
    }

    /// Creates a sketchbook: one white page, no video.
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
        pageSize = nil   // set by the canvas on first show
        clearPreset()
        frameStep = 1
        masks = [:]
        currentFrame = 0
        liveStroke = nil
        saveNow()
        writeThumbnail()
    }

    /// Starts a sketchbook over a grown-up's picture; the page takes the
    /// picture's shape.
    func createFromPicture(_ url: URL, faded: Bool) {
        guard let image = UIImage(contentsOfFile: url.path) else { return }
        createBlank()
        guard let dir = projectDirectory else { return }
        try? FileManager.default.copyItem(at: url, to: dir.appendingPathComponent(Self.pictureFileName))
        picture = image
        pictureFaded = faded
        pageSize = image.size
        saveNow()
        writeThumbnail()
    }

    /// Starts a new "따라 그리기" project from a bundled guide set.
    func createFromPreset(_ preset: GuidePreset) {
        stopPlayback()
        let dir = Self.projectsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch { return }
        source = nil
        videoURL = nil
        displayImage = nil
        projectDirectory = dir
        isBlank = false
        blankPageCount = 1
        presetId = preset.id
        guidePreset = preset
        picture = nil
        frameStep = 1
        masks = [:]
        currentFrame = 0
        liveStroke = nil
        refreshFrame()
        saveNow()
        writeThumbnail()
    }

    /// Clears whatever lay under the page: a guide set or a picture.
    private func clearPreset() {
        picture = nil
        presetId = nil
        guidePreset = nil
        guideImage = nil
    }

    /// Reopens a saved project folder.
    func openProject(at dir: URL) {
        stopPlayback()
        guard let json = try? Data(contentsOf: dir.appendingPathComponent("project.json")),
              let data = try? JSONDecoder().decode(ProjectData.self, from: json) else { return }

        if let pid = data.presetId, let preset = PresetLibrary.preset(id: pid) {
            source = nil
            videoURL = nil
            displayImage = nil
            isBlank = false
            blankPageCount = 1
            presetId = pid
            guidePreset = preset
        } else if data.isBlank || data.presetId != nil {
            // Blank flipbook — or a preset whose guides left the bundle; the
            // saved blankPageCount keeps the kid's drawings playable.
            source = nil
            videoURL = nil
            displayImage = nil
            isBlank = true
            blankPageCount = max(1, data.blankPageCount)
            pageSize = data.pageSize ?? Self.blankCanvasSize
            clearPreset()
            picture = UIImage(contentsOfFile: dir.appendingPathComponent(Self.pictureFileName).path)
            pictureFaded = data.pictureFaded ?? false
        } else {
            guard let name = data.videoFileName else { return }
            let vurl = dir.appendingPathComponent(name)
            Task {
                guard let src = await VideoSource.load(url: vurl) else { return }
                source = src
                videoURL = vurl
                isBlank = false
                blankPageCount = 1
                clearPreset()
                restore(data, from: dir)
            }
            return
        }
        restore(data, from: dir)
    }

    /// The part of reopening every kind of project shares: pages, drawings, position.
    private func restore(_ data: ProjectData, from dir: URL) {
        projectDirectory = dir
        frameStep = max(1, data.frameStep)
        hideBackground = data.hideBackground
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
        pageSize = nil
        clearPreset()
        hideBackground = false
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
        // A preset project stores its page count too, so it still opens as a
        // plain flipbook if the guide set ever disappears from the bundle.
        let data = ProjectData(frameStep: frameStep, currentFrame: currentFrame,
                               masks: masks, videoFileName: videoURL?.lastPathComponent,
                               isBlank: isBlank,
                               blankPageCount: isPreset ? frameCount : blankPageCount,
                               presetId: presetId, hideBackground: hideBackground,
                               pageSize: pageSize,
                               pictureFaded: picture == nil ? nil : pictureFaded)
        if let json = try? JSONEncoder().encode(data) {
            try? json.write(to: dir.appendingPathComponent("project.json"), options: .atomic)
        }
    }

    /// Home-grid thumbnail: the current frame (or white page) with its drawing.
    private func writeThumbnail() {
        guard let dir = projectDirectory else { return }
        Self.writeThumbnail(to: dir, base: displayImage, guide: guideImage ?? picture,
                            guideAlpha: picture == nil ? 0.6 : pictureOpacity,
                            mask: currentMask, canvasSize: canvasSize)
    }

    private static func writeThumbnail(to dir: URL, base: UIImage?, guide: UIImage?,
                                       guideAlpha: CGFloat = 0.6,
                                       mask: FrameMask, canvasSize: CGSize) {
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
                // The guide shows through so the card stays recognizable
                // even before the kid has traced anything.
                guide?.draw(in: CGRect(origin: .zero, size: size),
                            blendMode: .normal, alpha: guideAlpha)
            }
            if let paint = MaskRasterizer.paintLayer(for: mask, size: size) {
                UIImage(cgImage: paint).draw(in: CGRect(origin: .zero, size: size))
            }
        }
        try? data.write(to: dir.appendingPathComponent("thumb.png"))
        thumbnails.removeObject(forKey: dir as NSURL)
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
        // Hidden background: play only the pages the kid drew, back to back —
        // a long clip with 20 drawings becomes a 20-page flipbook on white.
        var playlist: [Int]?
        if hideBackground, source != nil {
            let drawn = drawnScenes
            if !drawn.isEmpty { playlist = drawn }
        }
        let pageCount = playlist?.count ?? frameCount
        guard pageCount > 1 else { return }
        isPlaying = true
        liveStroke = nil
        // Hidden background: the flipbook plays on a white page, so the kid
        // sees only their own drawing move.
        if hideBackground { displayImage = nil }
        let startIndex: Int
        if let playlist {
            startIndex = currentFrame >= playlist[playlist.count - 1]
                ? 0 : (playlist.firstIndex { $0 >= currentFrame } ?? 0)
        } else {
            startIndex = currentFrame >= frameCount - 1 ? 0 : currentFrame
        }
        // Scenes advance at the sampled rate, matching the exported result.
        let src = source
        let sceneFPS = src.map { Double($0.frameRate) / Double(frameStep) } ?? Self.blankFPS
        let clockStart = Date()

        // Recorded narration plays along (but not while re-recording it).
        if !isRecording, hasAudio, let audioURL,
           let player = try? AVAudioPlayer(contentsOf: audioURL) {
            audioPlayer = player
            player.currentTime = Double(startIndex) / sceneFPS
            player.play()
        }

        playbackTask = Task { [weak self] in
            while let self, self.isPlaying, !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(clockStart)
                let rawIndex = startIndex + Int(elapsed * sceneFPS)
                if !loop && rawIndex >= pageCount {
                    self.stopPlayback()   // single pass done (ends a dubbing take)
                    break
                }
                let target = playlist?[rawIndex % pageCount] ?? (rawIndex % pageCount)
                if target != self.currentFrame {
                    // Loop wrapped: a take recorded over several loops keeps
                    // playing through; once it has finished, the next wrap
                    // restarts it from the top in sync with the pictures.
                    if target < self.currentFrame, let player = self.audioPlayer,
                       !player.isPlaying {
                        player.currentTime = 0
                        player.play()
                    }
                    if let src, !self.hideBackground {
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
            displayImage = nil   // blank/preset: white page drawn by the canvas
            guideImage = guidePreset?.image(forScene: currentFrame)
            return
        }
        displayImage = src.uiImage(atFrame: videoFrame(forScene: currentFrame))
    }

    // MARK: - Mask access

    var currentMask: FrameMask { masks[currentFrame] ?? FrameMask() }

    /// Scenes the kid actually drew on, in page order. When the background
    /// is hidden, playback and export cover only these pages.
    var drawnScenes: [Int] {
        masks.filter { !$0.value.isEmpty }.keys.sorted()
    }

    func commitStroke(_ stroke: MaskStroke) {
        var m = masks[currentFrame] ?? FrameMask()
        m.strokes.append(stroke)
        masks[currentFrame] = m
        liveStroke = nil
        scheduleSave()
        writeThumbnail()
    }

    /// The trash button: the page goes blank, the drawing goes to the trash.
    func clearCurrentMask() {
        guard let m = masks[currentFrame], !m.isEmpty else { return }
        keepInTrash(m)
        masks[currentFrame] = FrameMask()
        scheduleSave()
        writeThumbnail()
    }

    func copyMaskFromPrevious() {
        guard currentFrame > 0, let prev = masks[currentFrame - 1] else { return }
        masks[currentFrame] = prev
        scheduleSave()
    }
}
