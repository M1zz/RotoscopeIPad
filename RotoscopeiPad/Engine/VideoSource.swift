import AVFoundation
import CoreImage
import UIKit

/// Wraps an AVAsset and gives precise, frame-indexed access to images.
final class VideoSource {
    let asset: AVAsset
    let track: AVAssetTrack
    let frameCount: Int
    let frameRate: Float
    let naturalSize: CGSize          // already transform-corrected

    private let generator: AVAssetImageGenerator

    // Downscaled generator + cache used for real-time playback preview.
    // Full-res decode with zero tolerance is far too slow for 30fps.
    private let previewGenerator: AVAssetImageGenerator
    private let previewCache = NSCache<NSNumber, UIImage>()

    init?(url: URL) {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        self.asset = asset
        self.track = track
        self.frameRate = track.nominalFrameRate > 0 ? track.nominalFrameRate : 30

        let dur = asset.duration
        let total = Int((CMTimeGetSeconds(dur) * Double(frameRate)).rounded())
        self.frameCount = max(total, 1)

        let raw = track.naturalSize
        let transformed = raw.applying(track.preferredTransform)
        self.naturalSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.maximumSize = .zero          // full resolution
        self.generator = gen

        let preview = AVAssetImageGenerator(asset: asset)
        preview.appliesPreferredTrackTransform = true
        preview.requestedTimeToleranceBefore = .zero
        preview.requestedTimeToleranceAfter = .zero
        preview.maximumSize = CGSize(width: 960, height: 960)
        self.previewGenerator = preview
        previewCache.totalCostLimit = 250 * 1024 * 1024   // ~250 MB of frames
    }

    func time(forFrame index: Int) -> CMTime {
        CMTimeMake(value: Int64(index), timescale: Int32(frameRate.rounded()))
    }

    /// Synchronous full-resolution frame fetch.
    func cgImage(atFrame index: Int) -> CGImage? {
        let t = time(forFrame: index)
        return try? generator.copyCGImage(at: t, actualTime: nil)
    }

    func uiImage(atFrame index: Int) -> UIImage? {
        guard let cg = cgImage(atFrame: index) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Downscaled frame for playback. Cached so looping playback stays smooth.
    func previewImage(atFrame index: Int) -> UIImage? {
        if let hit = previewCache.object(forKey: index as NSNumber) { return hit }
        let t = time(forFrame: index)
        guard let cg = try? previewGenerator.copyCGImage(at: t, actualTime: nil) else { return nil }
        let ui = UIImage(cgImage: cg)
        previewCache.setObject(ui, forKey: index as NSNumber, cost: cg.width * cg.height * 4)
        return ui
    }
}

// Immutable after init; NSCache and AVAssetImageGenerator are safe to use
// from the background decode task (one caller at a time).
extension VideoSource: @unchecked Sendable {}
