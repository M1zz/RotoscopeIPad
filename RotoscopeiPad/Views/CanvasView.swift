import SwiftUI
import UIKit

/// A UIView that captures touches, distinguishes Apple Pencil from finger,
/// and reports normalized stroke points back to the project. Drawing of the
/// image + mask overlays is done by SwiftUI on top; this view is transparent
/// and only handles input + computes the fitted rect.
final class DrawingInputView: UIView {
    var project: RotoProject?
    /// Called with a normalized point (0...1) and a phase.
    var onBegan: ((CGPoint) -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    /// `cancelled` is true when the system took the touch away.
    var onEnded: ((_ cancelled: Bool) -> Void)?
    /// Pencil hover / trackpad pointer position, nil when it leaves.
    var onHover: ((CGPoint?) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UIHoverGestureRecognizer(
            target: self, action: #selector(handleHover(_:))))
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)
        // VoiceOver 를 켜도 손가락으로 바로 그릴 수 있게 직접 조작 영역으로 둔다.
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "그림판")
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        switch g.state {
        case .began, .changed:
            onHover?(project?.isPlaying == true ? nil : normalized(g.location(in: self)))
        default:
            onHover?(nil)
        }
    }

    private func fittedRect() -> CGRect {
        guard let canvas = project?.canvasSize else { return bounds }
        let aspect = canvas.width / canvas.height
        var w = bounds.width, h = bounds.width / aspect
        if h > bounds.height { h = bounds.height; w = h * aspect }
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2,
                      width: w, height: h)
    }

    private func normalized(_ p: CGPoint) -> CGPoint {
        let r = fittedRect()
        let x = (p.x - r.minX) / r.width
        let y = (p.y - r.minY) / r.height
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    private func accept(_ touch: UITouch) -> Bool {
        guard project?.pencilOnly == true else { return true }
        return touch.type == .pencil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Tapping the canvas during playback pauses instead of drawing.
        if project?.isPlaying == true {
            project?.stopPlayback()
            return
        }
        guard let t = touches.first, accept(t) else { return }
        onBegan?(normalized(t.location(in: self)))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, accept(t) else { return }
        onMoved?(normalized(t.location(in: self)))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onEnded?(false)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onEnded?(true)
    }
}

struct DrawingInputBridge: UIViewRepresentable {
    @EnvironmentObject var project: RotoProject

    func makeUIView(context: Context) -> DrawingInputView {
        let v = DrawingInputView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = false
        v.project = project
        v.onBegan = { p in
            // Stamp tool: the stamp appears under the finger and is only
            // put down when the finger lifts, so it can be dragged into place.
            if project.tool == .stamp {
                project.heldStamp = p
                return
            }
            if project.tool == .move {
                project.grabShape(at: p)
                return
            }
            let additive = project.tool != .erase
            let closed = project.tool == .polygon
            project.liveStroke = MaskStroke(
                points: [p], isAdditive: additive, closed: closed,
                colorHex: project.brushColorHex, width: project.brushWidth,
                opacity: project.brushOpacity, smooth: project.brushSmoothing)
        }
        v.onMoved = { p in
            if project.heldStamp != nil {
                project.heldStamp = p
            } else if project.tool == .move {
                project.dragShape(to: p)
            } else {
                project.liveStroke?.points.append(p)
            }
        }
        v.onEnded = { cancelled in
            if project.tool == .move {
                project.dropShape()
            } else if let p = project.heldStamp {
                project.heldStamp = nil
                if !cancelled {
                    project.stamp(at: p)
                    Task { await NextPageTip.drewOnPage.donate() }
                }
            } else if let s = project.liveStroke, s.points.count > 1 {
                project.commitStroke(s)
                Task { await NextPageTip.drewOnPage.donate() }
            } else {
                project.liveStroke = nil
            }
        }
        v.onHover = { p in project.hoverPoint = p }
        return v
    }

    func updateUIView(_ v: DrawingInputView, context: Context) {
        v.project = project
    }
}

/// The visible canvas: frame image + onion skin + committed/live mask overlay,
/// with the transparent UIKit input view layered on top.
struct CanvasView: View {
    @EnvironmentObject var project: RotoProject

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = project.displayImage {
                    // While drawing, the footage washes out like tracing
                    // paper (white page + half-transparent video) so the
                    // kid's strokes stand out; playback with the background
                    // on shows the real video.
                    if !project.isPlaying {
                        Rectangle()
                            .fill(Color.white)
                            .aspectRatio(img.size.width / max(img.size.height, 1),
                                         contentMode: .fit)
                    }
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(project.isPlaying ? 1 : 0.5)
                } else if project.isOpen {
                    // White flipbook page (blank, preset, or a video playing
                    // with its background hidden).
                    Rectangle()
                        .fill(Color.white)
                        .aspectRatio(project.canvasSize.width / project.canvasSize.height,
                                     contentMode: .fit)
                    // A grown-up's picture under the sketchbook page.
                    if let picture = project.picture {
                        Image(uiImage: picture)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .opacity(project.pictureOpacity)
                            .allowsHitTesting(false)
                    }
                    // Tracing guide: visible while drawing, hidden during
                    // playback so only the kid's drawing animates.
                    if !project.isPlaying, let guide = project.guideImage {
                        Image(uiImage: guide)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .allowsHitTesting(false)
                    }
                }

                Canvas { ctx, size in
                    let rect = fittedRect(for: size)
                    if project.showOnionSkin, !project.isPlaying,
                       let prev = project.masks[project.currentFrame - 1] {
                        // Previous drawing shows through faintly in its real
                        // colors, like the last page of a flipbook.
                        var ghost = ctx
                        ghost.opacity = 0.3
                        drawMask(prev, in: ghost, rect: rect)
                    }
                    // Paint strokes into one layer so eraser strokes truly
                    // erase on screen (destinationOut) instead of drawing red.
                    ctx.drawLayer { layer in
                        var strokes = project.currentMask.strokes
                        if let live = project.liveStroke { strokes.append(live) }
                        for stroke in strokes {
                            layer.blendMode = stroke.isAdditive ? .normal : .destinationOut
                            drawStroke(stroke, in: layer, rect: rect)
                        }
                    }
                    // Hand tool: every shape that can be moved gets an outline
                    // in the hand's color, so the kid sees what to grab.
                    if project.tool == .move, !project.isPlaying {
                        drawMovableOutlines(in: ctx, rect: rect)
                    }
                    // A stamp held under the finger, not put down yet.
                    if let held = project.heldStamp {
                        drawStamp(at: held, in: ctx, rect: rect, held: true)
                    }
                    // Hovering pencil/pointer: ghost of what a touch would draw.
                    else if !project.isPlaying, project.liveStroke == nil,
                       let hover = project.hoverPoint {
                        drawHoverPreview(at: hover, in: ctx, rect: rect)
                    }
                }
                .allowsHitTesting(false)

                DrawingInputBridge()
            }
            // A new sketchbook's page takes this area's shape.
            .onChange(of: geo.size, initial: true) { _, size in project.fitPage(to: size) }
            .onChange(of: project.projectDirectory) { project.fitPage(to: geo.size) }
        }
    }

    private func fittedRect(for size: CGSize) -> CGRect {
        let canvas = project.canvasSize
        let aspect = canvas.width / canvas.height
        var w = size.width, h = size.width / aspect
        if h > size.height { h = size.height; w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    /// A halo around each movable shape (stamps and closed shapes). Pieces
    /// of one stamp merge: stroke them all wide, then cut their insides out,
    /// so only the outer edge of the whole shape remains.
    private func drawMovableOutlines(in ctx: GraphicsContext, rect: CGRect) {
        let pieces = project.currentMask.strokes
            .filter { $0.isAdditive && $0.closed }
            .map { stroke in
                Path(StrokeGeometry.path(points: stroke.points.map {
                    CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
                }, closed: true, smooth: stroke.smooth))
            }
        guard !pieces.isEmpty else { return }
        ctx.drawLayer { layer in
            for piece in pieces {
                layer.stroke(piece, with: .color(.green), style: StrokeStyle(lineWidth: 8, lineJoin: .round))
            }
            layer.blendMode = .destinationOut
            for piece in pieces { layer.fill(piece, with: .color(.black)) }
        }
    }

    /// The stamp as it would land at `p`. Hovering shows a faint dashed
    /// ghost; a stamp held under the finger shows almost solid, ready to drop.
    private func drawStamp(at p: CGPoint, in ctx: GraphicsContext,
                           rect: CGRect, held: Bool) {
        let color = Color(rgbHex: project.brushColorHex)
        let pieces = project.stampParts(centeredAt: p).map { part in
            Path(StrokeGeometry.path(points: part.points.map {
                CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
            }, closed: true, smooth: part.smooth))
        }
        // Pieces overlap: fill them opaque in one layer, then fade the
        // whole layer, so the stamp is one even shape.
        var layerCtx = ctx
        layerCtx.opacity = held ? 0.75 * project.brushOpacity : 0.22
        layerCtx.drawLayer { layer in
            for piece in pieces { layer.fill(piece, with: .color(color)) }
        }
        guard !held else { return }
        for piece in pieces {
            ctx.stroke(piece, with: .color(color.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
    }

    /// Ghost preview under a hovering pencil/pointer: the stamp outline for
    /// the stamp tool, otherwise a circle the size of the brush/eraser tip.
    private func drawHoverPreview(at p: CGPoint, in ctx: GraphicsContext,
                                  rect: CGRect) {
        if project.tool == .stamp {
            drawStamp(at: p, in: ctx, rect: rect, held: false)
        } else if project.tool != .move {
            let d = max(project.brushWidth * min(rect.width, rect.height), 6)
            let tip = CGRect(x: rect.minX + p.x * rect.width - d / 2,
                             y: rect.minY + p.y * rect.height - d / 2,
                             width: d, height: d)
            let path = Path(ellipseIn: tip)
            if project.tool == .erase {
                ctx.fill(path, with: .color(.white.opacity(0.55)))
                ctx.stroke(path, with: .color(.gray.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            } else {
                let color = Color(rgbHex: project.brushColorHex)
                ctx.fill(path, with: .color(color.opacity(0.35)))
                ctx.stroke(path, with: .color(color.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 2))
            }
        }
    }

    /// Draws every stroke of a mask into its own layer (so erases apply),
    /// using each stroke's real color.
    private func drawMask(_ mask: FrameMask, in ctx: GraphicsContext,
                          rect: CGRect) {
        ctx.drawLayer { layer in
            for stroke in mask.strokes {
                layer.blendMode = stroke.isAdditive ? .normal : .destinationOut
                drawStroke(stroke, in: layer, rect: rect)
            }
        }
    }

    private func drawStroke(_ stroke: MaskStroke, in ctx: GraphicsContext,
                            rect: CGRect, tint: Color? = nil) {
        guard stroke.points.count > 1 else { return }
        let pts = stroke.points.map {
            CGPoint(x: rect.minX + $0.x * rect.width,
                    y: rect.minY + $0.y * rect.height)
        }
        let path = Path(StrokeGeometry.path(points: pts, closed: stroke.closed,
                                            smooth: stroke.smooth))

        let base: Color = tint ?? Color(rgbHex: stroke.colorHex)
        let alpha = tint == nil ? stroke.opacity : 1.0
        let lineW = max(stroke.width * min(rect.width, rect.height), 1)

        if stroke.closed {
            ctx.fill(path, with: .color(base.opacity(alpha * 0.85)))
        }
        ctx.stroke(path, with: .color(base.opacity(alpha)),
                   style: StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Apple Pencil 두 번 탭

extension DrawingInputView: UIPencilInteractionDelegate {
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        handlePencilTap()
    }

    // iOS 17.0–17.4
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        handlePencilTap()
    }

    private func handlePencilTap() {
        switch UIPencilInteraction.preferredTapAction {
        case .switchEraser: project?.pencilDoubleTap(switchToPrevious: false)
        case .switchPrevious: project?.pencilDoubleTap(switchToPrevious: true)
        default: break   // 끄기 · 색 팔레트 등 — 사용자가 고른 대로 아무것도 안 한다
        }
    }
}
