import Foundation
import CoreGraphics

/// One filled piece of a stamp: a closed outline in unit space
/// (x and y in [-1, 1], +y pointing down).
struct StampPart {
    var points: [CGPoint]
    var smooth: Bool
}

/// Tap-to-stamp shapes (도장), each built from a few simple pieces — circles,
/// ovals and polygons — so a kid recognizes them at a glance. A stamp lands
/// as normal closed strokes (one per piece, same color, so they read as one
/// shape), and draws, plays back, exports and erases like painted strokes.
///
/// The whole set is a library; a grown-up picks up to `limit` of them in
/// Settings, and only those show on the kid's toolbar.
enum StampShape: String, CaseIterable, Identifiable {
    // 도형
    case circle, square, triangle, heart, star, diamond, moon, drop, cloud, flower
    // 동물
    case cat, bear, rabbit, fish, bird, butterfly
    // 물건
    case house, tree, car, rocket, sun, iceCream

    var id: String { rawValue }

    enum Kind: CaseIterable { case shapes, animals, things }

    var kind: Kind {
        switch self {
        case .circle, .square, .triangle, .heart, .star, .diamond, .moon, .drop, .cloud, .flower:
            return .shapes
        case .cat, .bear, .rabbit, .fish, .bird, .butterfly:
            return .animals
        case .house, .tree, .car, .rocket, .sun, .iceCream:
            return .things
        }
    }

    // MARK: - The kid's toolbar

    /// At most this many stamps on the toolbar — more is too many to choose from.
    static let limit = 10
    /// Settings key: the picked stamps' ids, comma-separated ("" = none).
    static let storageKey = "stamps"
    static let starterIDs = [StampShape.heart, .circle, .square, .triangle, .star,
                             .flower, .cat, .car].map(\.rawValue).joined(separator: ",")

    /// The picked stamps, in library order, never more than `limit`.
    static func chosen(_ ids: String) -> [StampShape] {
        let picked = Set(ids.split(separator: ",").map(String.init))
        return Array(allCases.filter { picked.contains($0.rawValue) }.prefix(limit))
    }

    // MARK: - Pieces

    var parts: [StampPart] {
        switch self {
        case .circle:
            return [Self.oval(0, 0, 0.95, 0.95)]
        case .square:
            return [Self.poly((-0.85, -0.85), (0.85, -0.85), (0.85, 0.85), (-0.85, 0.85))]
        case .triangle:
            return [Self.poly((0, -0.95), (0.95, 0.8), (-0.95, 0.8))]
        case .heart:
            // Classic heart curve, flipped so the tip points down on screen.
            return [StampPart(points: Self.sweep(36) { t in
                let x = 16 * pow(sin(t), 3)
                let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
                return CGPoint(x: x / 17, y: -y / 17)
            }, smooth: true)]
        case .star:
            // Five points: outer/inner radii alternate, starting straight up.
            return [StampPart(points: (0..<10).map { k in
                let angle = -CGFloat.pi / 2 + CGFloat(k) * .pi / 5
                let radius: CGFloat = k.isMultiple(of: 2) ? 1 : 0.42
                return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            }, smooth: false)]
        case .diamond:
            return [Self.poly((0, -1), (0.72, 0), (0, 1), (-0.72, 0))]
        case .moon:
            return [Self.crescent]
        case .drop:
            // Teardrop: round at the bottom, a point at the top.
            return [StampPart(points: Self.sweep(48) { t in
                CGPoint(x: 1.1 * sin(t) * sin(t / 2), y: -cos(t) * 0.95)
            }, smooth: false)]
        case .cloud:
            return [Self.oval(-0.5, 0.15, 0.42, 0.42), Self.oval(0, -0.15, 0.52, 0.52),
                    Self.oval(0.5, 0.15, 0.42, 0.42),
                    Self.poly((-0.5, 0.15), (0.5, 0.15), (0.5, 0.57), (-0.5, 0.57))]
        case .flower:
            let petals = (0..<5).map { k -> StampPart in
                let a = -CGFloat.pi / 2 + CGFloat(k) * 2 * .pi / 5
                return Self.oval(cos(a) * 0.55, sin(a) * 0.55, 0.38, 0.38)
            }
            return petals + [Self.oval(0, 0, 0.32, 0.32)]

        case .cat:
            return [Self.oval(0, 0.15, 0.8, 0.7),
                    Self.poly((-0.78, -0.2), (-0.62, -0.95), (-0.18, -0.5)),
                    Self.poly((0.78, -0.2), (0.62, -0.95), (0.18, -0.5))]
        case .bear:
            return [Self.oval(-0.58, -0.55, 0.3, 0.3), Self.oval(0.58, -0.55, 0.3, 0.3),
                    Self.oval(0, 0.12, 0.78, 0.75)]
        case .rabbit:
            return [Self.oval(-0.25, -0.45, 0.17, 0.48), Self.oval(0.25, -0.45, 0.17, 0.48),
                    Self.oval(0, 0.4, 0.55, 0.55)]
        case .fish:
            return [Self.oval(-0.15, 0, 0.68, 0.45),
                    Self.poly((0.35, 0), (0.97, -0.48), (0.97, 0.48))]
        case .bird:
            return [Self.oval(0.08, 0.22, 0.65, 0.5), Self.oval(-0.42, -0.35, 0.32, 0.32),
                    Self.poly((-0.68, -0.42), (-1, -0.3), (-0.68, -0.2)),
                    Self.poly((0.55, 0.05), (0.98, -0.28), (0.88, 0.35))]
        case .butterfly:
            return [Self.oval(-0.45, -0.3, 0.45, 0.42), Self.oval(0.45, -0.3, 0.45, 0.42),
                    Self.oval(-0.35, 0.42, 0.33, 0.3), Self.oval(0.35, 0.42, 0.33, 0.3),
                    Self.oval(0, 0, 0.1, 0.72)]

        case .house:
            return [Self.poly((0, -0.92), (0.95, -0.05), (-0.95, -0.05)),
                    Self.poly((-0.65, -0.1), (0.65, -0.1), (0.65, 0.9), (-0.65, 0.9))]
        case .tree:
            return [Self.oval(0, -0.3, 0.65, 0.65),
                    Self.poly((-0.15, 0.2), (0.15, 0.2), (0.15, 0.95), (-0.15, 0.95))]
        case .car:
            return [Self.poly((-0.5, -0.05), (-0.3, -0.5), (0.35, -0.5), (0.55, -0.05)),
                    Self.poly((-0.95, -0.05), (0.95, -0.05), (0.95, 0.45), (-0.95, 0.45)),
                    Self.oval(-0.5, 0.5, 0.25, 0.25), Self.oval(0.5, 0.5, 0.25, 0.25)]
        case .rocket:
            return [Self.poly((0, -0.98), (0.3, -0.33), (-0.3, -0.33)),
                    Self.poly((-0.3, -0.35), (0.3, -0.35), (0.3, 0.6), (-0.3, 0.6)),
                    Self.poly((-0.3, 0.12), (-0.65, 0.78), (-0.3, 0.6)),
                    Self.poly((0.3, 0.12), (0.65, 0.78), (0.3, 0.6))]
        case .sun:
            let rays = (0..<8).map { k -> StampPart in
                let a = CGFloat(k) * .pi / 4
                func at(_ r: CGFloat, _ da: CGFloat) -> (CGFloat, CGFloat) {
                    (cos(a + da) * r, sin(a + da) * r)
                }
                return Self.poly(at(1, 0), at(0.5, 0.13), at(0.5, -0.13))
            }
            return rays + [Self.oval(0, 0, 0.55, 0.55)]
        case .iceCream:
            return [Self.poly((-0.45, -0.02), (0.45, -0.02), (0, 0.98)),
                    Self.oval(0, -0.38, 0.5, 0.5)]
        }
    }

    // MARK: - Building blocks

    private static func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> StampPart {
        StampPart(points: sweep(48) { CGPoint(x: cx + cos($0) * rx, y: cy + sin($0) * ry) },
                  smooth: false)
    }

    private static func poly(_ points: (CGFloat, CGFloat)...) -> StampPart {
        StampPart(points: points.map { CGPoint(x: $0.0, y: $0.1) }, smooth: false)
    }

    /// The moon: the part of one circle outside a second, shifted one.
    private static var crescent: StampPart {
        let outer = (c: CGPoint(x: 0, y: 0), r: CGFloat(0.92))
        let inner = (c: CGPoint(x: 0.42, y: -0.2), r: CGFloat(0.75))
        func on(_ circle: (c: CGPoint, r: CGFloat), _ t: CGFloat) -> CGPoint {
            CGPoint(x: circle.c.x + cos(t) * circle.r, y: circle.c.y + sin(t) * circle.r)
        }
        func inside(_ p: CGPoint, _ circle: (c: CGPoint, r: CGFloat)) -> Bool {
            hypot(p.x - circle.c.x, p.y - circle.c.y) < circle.r
        }
        let rim = sweep(96) { on(outer, $0) }.filter { !inside($0, inner) }
        let bite = sweep(96) { on(inner, $0) }.filter { inside($0, outer) }
        return StampPart(points: rim + bite.reversed(), smooth: false)
    }

    private static func sweep(_ count: Int, _ point: (CGFloat) -> CGPoint) -> [CGPoint] {
        (0..<count).map { point(CGFloat($0) / CGFloat(count) * 2 * .pi) }
    }
}
