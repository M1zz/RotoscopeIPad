import CoreGraphics
import CoreImage

/// Converts a FrameMask (vector strokes) into a raster alpha mask and
/// applies it to a source frame to produce a cut-out RGBA image.
enum MaskRasterizer {

    /// Builds a grayscale alpha mask at the given pixel size.
    /// White (255) = keep, black (0) = transparent.
    static func alphaMask(for frameMask: FrameMask, size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return nil }

        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }

        // Start fully transparent (black).
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        for stroke in frameMask.strokes where stroke.points.count > 1 {
            let pts = stroke.points.map { CGPoint(x: $0.x * size.width,
                                                  y: (1 - $0.y) * size.height) } // flip Y
            let path = StrokeGeometry.path(points: pts, closed: stroke.closed,
                                           smooth: stroke.smooth)

            if stroke.closed {
                ctx.addPath(path)
                ctx.setFillColor(gray: stroke.isAdditive ? 1 : 0, alpha: 1)
                ctx.fillPath()
            } else {
                ctx.setStrokeColor(gray: stroke.isAdditive ? 1 : 0, alpha: 1)
                ctx.setLineWidth(max(stroke.width * min(size.width, size.height), 1))
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        return ctx.makeImage()
    }

    /// Renders the colored paint strokes of a frame over a transparent canvas
    /// at the given pixel size. Additive strokes paint their color; erase
    /// strokes clear pixels back to transparent (so paint can be trimmed).
    static func paintLayer(for frameMask: FrameMask, size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        for stroke in frameMask.strokes where stroke.points.count > 1 {
            let pts = stroke.points.map { CGPoint(x: $0.x * size.width,
                                                  y: (1 - $0.y) * size.height) } // flip Y
            let path = StrokeGeometry.path(points: pts, closed: stroke.closed,
                                           smooth: stroke.smooth)
            let rgb = stroke.colorHex.rgbComponents

            ctx.setBlendMode(stroke.isAdditive ? .normal : .clear)
            ctx.setLineWidth(max(stroke.width * min(size.width, size.height), 1))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            if stroke.closed {
                ctx.addPath(path)
                ctx.setFillColor(red: rgb.r, green: rgb.g, blue: rgb.b,
                                 alpha: stroke.isAdditive ? stroke.opacity * 0.85 : 1)
                ctx.fillPath()
                // Outline the fill so closed shapes keep a crisp colored edge.
                ctx.addPath(path)
                ctx.setStrokeColor(red: rgb.r, green: rgb.g, blue: rgb.b,
                                   alpha: stroke.isAdditive ? stroke.opacity : 1)
                ctx.strokePath()
            } else {
                ctx.addPath(path)
                ctx.setStrokeColor(red: rgb.r, green: rgb.g, blue: rgb.b,
                                   alpha: stroke.isAdditive ? stroke.opacity : 1)
                ctx.strokePath()
            }
        }
        return ctx.makeImage()
    }

    /// Composites the colored paint layer over a source frame, returning an
    /// RGBA image. Used by the export pass so drawn animation is baked in.
    static func painted(source: CGImage, frameMask: FrameMask) -> CGImage? {
        let w = source.width, h = source.height
        guard w > 0, h > 0,
              let paint = paintLayer(for: frameMask, size: CGSize(width: w, height: h)) else {
            return source
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(source, in: rect)
        ctx.draw(paint, in: rect)
        return ctx.makeImage()
    }

    /// Applies an alpha mask to a source frame, returning a transparent cut-out.
    static func cutout(source: CGImage, frameMask: FrameMask) -> CGImage? {
        let size = CGSize(width: source.width, height: source.height)
        guard let mask = alphaMask(for: frameMask, size: size) else { return source }

        let ci = CIImage(cgImage: source)
        let maskCI = CIImage(cgImage: mask)
        let clear = CIImage(color: .clear).cropped(to: ci.extent)

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return source }
        blend.setValue(ci, forKey: kCIInputImageKey)
        blend.setValue(clear, forKey: kCIInputBackgroundImageKey)
        blend.setValue(maskCI, forKey: kCIInputMaskImageKey)

        guard let out = blend.outputImage else { return source }
        let ctx = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        return ctx.createCGImage(out, from: ci.extent)
    }
}
