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
    var onEnded: (() -> Void)?
    /// Pencil hover / trackpad pointer position, nil when it leaves.
    var onHover: ((CGPoint?) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UIHoverGestureRecognizer(
            target: self, action: #selector(handleHover(_:))))
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
        onEnded?()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onEnded?()
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
            // Stamp tool: one tap, one stamp — no live stroke.
            if project.tool == .stamp {
                project.stamp(at: p)
                return
            }
            let additive = project.tool != .erase
            let closed = project.tool == .polygon
            project.liveStroke = MaskStroke(
                points: [p], isAdditive: additive, closed: closed,
                colorHex: project.brushColorHex, width: project.brushWidth,
                opacity: project.brushOpacity, smooth: project.brushSmoothing)
        }
        v.onMoved = { p in project.liveStroke?.points.append(p) }
        v.onEnded = {
            if let s = project.liveStroke, s.points.count > 1 {
                project.commitStroke(s)
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
                    // Hovering pencil/pointer: ghost of what a touch would draw.
                    if !project.isPlaying, project.liveStroke == nil,
                       let hover = project.hoverPoint {
                        drawHoverPreview(at: hover, in: ctx, rect: rect)
                    }
                }
                .allowsHitTesting(false)

                DrawingInputBridge()
            }
        }
    }

    private func fittedRect(for size: CGSize) -> CGRect {
        let canvas = project.canvasSize
        let aspect = canvas.width / canvas.height
        var w = size.width, h = size.width / aspect
        if h > size.height { h = size.height; w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    /// Ghost preview under a hovering pencil/pointer: the stamp outline for
    /// the stamp tool, otherwise a circle the size of the brush/eraser tip.
    private func drawHoverPreview(at p: CGPoint, in ctx: GraphicsContext,
                                  rect: CGRect) {
        if project.tool == .stamp {
            let pts = project.stampPoints(centeredAt: p).map {
                CGPoint(x: rect.minX + $0.x * rect.width,
                        y: rect.minY + $0.y * rect.height)
            }
            guard pts.count > 1 else { return }
            let path = Path(StrokeGeometry.path(points: pts, closed: true,
                                                smooth: project.stampShape.smooth))
            let color = Color(hex: project.brushColorHex)
            ctx.fill(path, with: .color(color.opacity(0.22)))
            ctx.stroke(path, with: .color(color.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        } else {
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
                let color = Color(hex: project.brushColorHex)
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

        let base: Color = tint ?? Color(hex: stroke.colorHex)
        let alpha = tint == nil ? stroke.opacity : 1.0
        let lineW = max(stroke.width * min(rect.width, rect.height), 1)

        if stroke.closed {
            ctx.fill(path, with: .color(base.opacity(alpha * 0.85)))
        }
        ctx.stroke(path, with: .color(base.opacity(alpha)),
                   style: StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round))
    }
}
