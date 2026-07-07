import Foundation
import CoreGraphics

/// A single path the user draws to define a mask region.
/// Points are stored in normalized [0,1] coordinates so masks survive
/// resolution changes between the preview and the export pass.
struct MaskStroke: Identifiable, Codable, Equatable {
    var id = UUID()
    var points: [CGPoint]          // normalized 0...1
    var isAdditive: Bool           // true = include region, false = erase region
    var closed: Bool               // closed polygons fill; open strokes act as a brush

    // Paint attributes — how the stroke looks on screen and in the export.
    var colorHex: String           // RRGGBB paint color
    var width: Double              // brush width as a fraction of the frame's min dimension
    var opacity: Double            // 0...1
    var smooth: Bool               // Catmull-Rom smoothing of the point chain

    init(points: [CGPoint] = [], isAdditive: Bool = true, closed: Bool = true,
         colorHex: String = "FF3B30", width: Double = 0.012,
         opacity: Double = 1.0, smooth: Bool = true) {
        self.points = points
        self.isAdditive = isAdditive
        self.closed = closed
        self.colorHex = colorHex
        self.width = width
        self.opacity = opacity
        self.smooth = smooth
    }

    // Decode with defaults so strokes saved before paint attributes existed
    // (or partial payloads) still load cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        points = try c.decode([CGPoint].self, forKey: .points)
        isAdditive = try c.decodeIfPresent(Bool.self, forKey: .isAdditive) ?? true
        closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? true
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "FF3B30"
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 0.012
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        smooth = try c.decodeIfPresent(Bool.self, forKey: .smooth) ?? true
    }
}

/// All the mask data belonging to one video frame.
struct FrameMask: Codable, Equatable {
    var strokes: [MaskStroke] = []
    var isEmpty: Bool { strokes.allSatisfy { $0.points.isEmpty } }
}

// CGPoint already conforms to Codable on iOS 13+ via CoreGraphics,
// so MaskStroke/FrameMask get synthesized Codable for free.
