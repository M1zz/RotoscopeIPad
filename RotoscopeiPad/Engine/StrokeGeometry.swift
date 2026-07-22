import SwiftUI
import UIKit
import CoreGraphics

/// Geometry + color helpers shared by the live canvas and the export
/// rasterizer, so what you see on screen matches what gets baked out.
enum StrokeGeometry {

    /// Builds a CGPath through the given points. When `smooth` is true the
    /// points are connected with a Catmull-Rom spline (converted to cubic
    /// Béziers) so hand-drawn strokes read as smooth curves instead of a
    /// chain of straight segments.
    static func path(points: [CGPoint], closed: Bool, smooth: Bool) -> CGPath {
        let path = CGMutablePath()
        guard points.count > 1 else { return path }

        guard smooth, points.count > 2 else {
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
            if closed { path.closeSubpath() }
            return path
        }

        let n = points.count
        path.move(to: points[0])
        let upper = closed ? n : n - 1
        for i in 0..<upper {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i % n]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            // Endpoints of an open stroke clamp to their neighbour so the
            // curve doesn't overshoot past the drawn line.
            let a = (i == 0 && !closed) ? p1 : p0
            let b = (i >= n - 2 && !closed) ? p2 : p3
            let c1 = CGPoint(x: p1.x + (p2.x - a.x) / 6.0,
                             y: p1.y + (p2.y - a.y) / 6.0)
            let c2 = CGPoint(x: p2.x - (b.x - p1.x) / 6.0,
                             y: p2.y - (b.y - p1.y) / 6.0)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        if closed { path.closeSubpath() }
        return path
    }
}

extension Color {
    /// Creates a Color from a 6-digit RRGGBB hex string (no leading '#').
    /// Named `rgbHex` to avoid colliding with LeeoKit's failable `Color(hex:)`.
    init(rgbHex hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    /// The RRGGBB hex string for this color (best effort, sRGB).
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

extension String {
    /// Parses this RRGGBB hex into RGB components (0...1) for CoreGraphics.
    var rgbComponents: (r: CGFloat, g: CGFloat, b: CGFloat) {
        let s = hasPrefix("#") ? String(dropFirst()) : self
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        return (CGFloat((v >> 16) & 0xFF) / 255.0,
                CGFloat((v >> 8) & 0xFF) / 255.0,
                CGFloat(v & 0xFF) / 255.0)
    }
}
