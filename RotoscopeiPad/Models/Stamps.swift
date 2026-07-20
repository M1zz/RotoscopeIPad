import CoreGraphics

/// Tap-to-stamp shapes (도장). Each stamp is committed as a normal closed
/// MaskStroke, so it draws, plays back, exports, erases and undoes exactly
/// like painted strokes — no special cases anywhere else.
enum StampShape: String, CaseIterable, Identifiable {
    case heart, circle, square, triangle
    case star, flower, car, bird

    var id: String { rawValue }

    /// Icon-only button symbol.
    var symbol: String {
        switch self {
        case .heart:    return "heart.fill"
        case .circle:   return "circle.fill"
        case .square:   return "square.fill"
        case .triangle: return "triangle.fill"
        case .star:     return "star.fill"
        case .flower:   return "camera.macro"
        case .car:      return "car.fill"
        case .bird:     return "bird.fill"
        }
    }

    /// Hard-cornered shapes keep straight edges; organic ones get the same
    /// Catmull-Rom smoothing as hand-drawn strokes.
    var smooth: Bool {
        switch self {
        case .square, .triangle, .star: return false
        default: return true
        }
    }

    /// Closed outline in unit space: x and y in [-1, 1], +y pointing down.
    var unitPoints: [CGPoint] {
        switch self {
        case .circle:
            return Self.parametric(count: 24) { t in
                CGPoint(x: cos(t), y: sin(t))
            }

        case .heart:
            // Classic heart curve, scaled into the unit box and flipped so
            // the tip points down on screen.
            return Self.parametric(count: 36) { t in
                let x = 16 * pow(sin(t), 3)
                let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
                return CGPoint(x: x / 17, y: -y / 17)
            }

        case .square:
            return [CGPoint(x: -0.8, y: -0.8), CGPoint(x: 0.8, y: -0.8),
                    CGPoint(x: 0.8, y: 0.8), CGPoint(x: -0.8, y: 0.8)]

        case .triangle:
            return [CGPoint(x: 0, y: -0.95), CGPoint(x: 0.95, y: 0.75),
                    CGPoint(x: -0.95, y: 0.75)]

        case .star:
            // Five points: outer/inner radii alternate, starting straight up.
            return (0..<10).map { k in
                let angle = -CGFloat.pi / 2 + CGFloat(k) * .pi / 5
                let radius: CGFloat = k.isMultiple(of: 2) ? 1 : 0.42
                return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            }

        case .flower:
            // Five petals: radius swells and dips as the angle sweeps around.
            return Self.parametric(count: 60) { t in
                let r = 0.4 + 0.6 * abs(cos(2.5 * t))
                return CGPoint(x: cos(t) * r, y: sin(t) * r)
            }

        case .car:
            // Side-view silhouette with wheel bumps; smoothing rounds it
            // into a friendly cartoon car.
            return [
                CGPoint(x: -1.00, y: 0.10),   // front bumper
                CGPoint(x: -0.60, y: 0.00),   // hood
                CGPoint(x: -0.40, y: -0.45),  // windshield
                CGPoint(x: 0.35, y: -0.45),   // roof
                CGPoint(x: 0.60, y: -0.05),   // rear window
                CGPoint(x: 1.00, y: 0.05),    // trunk
                CGPoint(x: 1.00, y: 0.50),    // rear bumper
                CGPoint(x: 0.80, y: 0.50),
                CGPoint(x: 0.75, y: 0.70),    // rear wheel bump
                CGPoint(x: 0.55, y: 0.78),
                CGPoint(x: 0.35, y: 0.70),
                CGPoint(x: 0.30, y: 0.50),
                CGPoint(x: -0.30, y: 0.50),   // between the wheels
                CGPoint(x: -0.35, y: 0.70),   // front wheel bump
                CGPoint(x: -0.55, y: 0.78),
                CGPoint(x: -0.75, y: 0.70),
                CGPoint(x: -0.80, y: 0.50),
                CGPoint(x: -1.00, y: 0.50)
            ]

        case .bird:
            // Bird facing right: tail, back, head, beak, chest, belly.
            return [
                CGPoint(x: -0.90, y: 0.00),   // tail tip
                CGPoint(x: -0.50, y: -0.15),  // back
                CGPoint(x: 0.10, y: -0.35),   // neck
                CGPoint(x: 0.45, y: -0.55),   // head top
                CGPoint(x: 0.75, y: -0.45),   // head front
                CGPoint(x: 1.00, y: -0.30),   // beak tip
                CGPoint(x: 0.75, y: -0.25),   // beak bottom
                CGPoint(x: 0.55, y: -0.10),   // chest
                CGPoint(x: 0.35, y: 0.30),    // belly
                CGPoint(x: -0.15, y: 0.50),   // underside
                CGPoint(x: -0.60, y: 0.35)    // tail underside
            ]
        }
    }

    private static func parametric(count: Int,
                                   _ point: (CGFloat) -> CGPoint) -> [CGPoint] {
        (0..<count).map { point(CGFloat($0) / CGFloat(count) * 2 * .pi) }
    }
}
