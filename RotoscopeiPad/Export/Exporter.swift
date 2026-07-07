import AVFoundation
import CoreImage
import UIKit
import Photos

/// Writes cut-out frames as a PNG sequence and a transparent ProRes 4444
/// .mov into a folder under the app's Documents directory (visible in Files
/// when UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace are set).
@MainActor
final class Exporter {

    struct Options {
        var writePNGSequence = true
        var writeProRes = true
        /// Also writes an H.264 .mp4 (no alpha — Photos can't show it anyway)
        /// and saves it to the photo library.
        var saveToPhotos = false
    }

    let project: RotoProject
    init(project: RotoProject) { self.project = project }

    /// Creates a unique output folder and runs the export.
    /// Returns the folder URL so the UI can offer a share sheet.
    func export(options: Options,
                progress: @escaping (Double) -> Void) async throws -> URL {
        guard project.isOpen else { throw ExportError.noSource }
        let src = project.source   // nil for blank flipbook projects
        let size = project.canvasSize
        let fps = Int32(src?.frameRate.rounded() ?? Float(RotoProject.blankFPS))

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let folder = docs.appendingPathComponent("Rotoscope_\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Scenes (sampled frames), not raw video frames — each drawn scene is
        // held for frameStep video frames so timing matches the original clip.
        let total = project.frameCount
        let pngDir = folder.appendingPathComponent("png_sequence", isDirectory: true)
        if options.writePNGSequence {
            try FileManager.default.createDirectory(at: pngDir, withIntermediateDirectories: true)
        }

        // Movie writers: ProRes 4444 (alpha-capable) for compositing work,
        // and H.264 mp4 (opaque) for the photo library / easy playback.
        func makeWriter(url: URL, fileType: AVFileType, codec: AVVideoCodecType)
            throws -> (AVAssetWriter, AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor) {
            let w = try AVAssetWriter(outputURL: url, fileType: fileType)
            let settings: [String: Any] = [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height)
            ]
            let inp = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            inp.expectsMediaDataInRealTime = false
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
            let adp = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp,
                                                           sourcePixelBufferAttributes: attrs)
            w.add(inp)
            w.startWriting()
            w.startSession(atSourceTime: .zero)
            return (w, inp, adp)
        }

        var writer: AVAssetWriter?
        var input: AVAssetWriterInput?
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        let movURL = folder.appendingPathComponent("rotoscope_alpha.mov")
        if options.writeProRes {
            (writer, input, adaptor) = try makeWriter(url: movURL, fileType: .mov,
                                                      codec: .proRes4444)
        }

        var mp4Writer: AVAssetWriter?
        var mp4Input: AVAssetWriterInput?
        var mp4Adaptor: AVAssetWriterInputPixelBufferAdaptor?
        let mp4URL = folder.appendingPathComponent("rotoscope.mp4")
        if options.saveToPhotos {
            (mp4Writer, mp4Input, mp4Adaptor) = try makeWriter(url: mp4URL, fileType: .mp4,
                                                               codec: .h264)
        }

        let ciContext = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])

        // Blank flipbook pages share one white background image.
        let whitePage: CGImage? = src == nil ? Self.whiteImage(size: size) : nil

        for scene in 0..<total {
            let videoFrame = project.videoFrame(forScene: scene)
            guard let srcImage = src?.cgImage(atFrame: videoFrame) ?? whitePage else { continue }
            let mask = project.masks[scene] ?? FrameMask()
            let rendered: CGImage
            switch project.renderMode {
            case .paint:
                rendered = MaskRasterizer.painted(source: srcImage, frameMask: mask) ?? srcImage
            case .cutout:
                rendered = MaskRasterizer.cutout(source: srcImage, frameMask: mask) ?? srcImage
            }

            if options.writePNGSequence {
                let name = String(format: "frame_%05d.png", scene)
                try writePNG(rendered, to: pngDir.appendingPathComponent(name))
            }

            // Presentation time uses the underlying video frame index, so each
            // drawn scene holds on screen for frameStep frames of real time.
            // Blank projects run one page per tick at blankFPS.
            let t = CMTimeMake(value: Int64(src == nil ? scene : videoFrame), timescale: fps)
            if let adaptor, let input {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                if let buffer = pixelBuffer(from: rendered, size: size,
                                            context: ciContext,
                                            pool: adaptor.pixelBufferPool) {
                    adaptor.append(buffer, withPresentationTime: t)
                }
            }
            if let mp4Adaptor, let mp4Input {
                while !mp4Input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                if let buffer = pixelBuffer(from: rendered, size: size,
                                            context: ciContext,
                                            pool: mp4Adaptor.pixelBufferPool) {
                    mp4Adaptor.append(buffer, withPresentationTime: t)
                }
            }

            let p = Double(scene + 1) / Double(total)
            await MainActor.run { progress(p) }
        }

        // End at the clip's full duration so the last held scene keeps its length.
        let endTime = CMTimeMake(value: Int64(src?.frameCount ?? total), timescale: fps)
        if let input, let writer {
            input.markAsFinished()
            writer.endSession(atSourceTime: endTime)
            await writer.finishWriting()
        }
        if let mp4Input, let mp4Writer {
            mp4Input.markAsFinished()
            mp4Writer.endSession(atSourceTime: endTime)
            await mp4Writer.finishWriting()
        }

        if options.saveToPhotos {
            // Mux in the kid's narration when it exists.
            var finalURL = mp4URL
            if let audioURL = project.audioURL, project.hasAudio {
                finalURL = (try? await muxAudio(video: mp4URL, audio: audioURL)) ?? mp4URL
            }
            try await saveVideoToPhotos(url: finalURL)
        }
        return folder
    }

    /// Combines the silent video with the narration track into one mp4.
    private func muxAudio(video videoURL: URL, audio audioURL: URL) async throws -> URL {
        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let vTrack = videoTracks.first, let aTrack = audioTracks.first else {
            return videoURL
        }

        let comp = AVMutableComposition()
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        guard let cv = comp.addMutableTrack(withMediaType: .video,
                                            preferredTrackID: kCMPersistentTrackID_Invalid),
              let ca = comp.addMutableTrack(withMediaType: .audio,
                                            preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return videoURL
        }
        try cv.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration),
                               of: vTrack, at: .zero)
        try ca.insertTimeRange(CMTimeRange(start: .zero,
                                           duration: CMTimeMinimum(audioDuration, videoDuration)),
                               of: aTrack, at: .zero)

        let outURL = videoURL.deletingLastPathComponent()
            .appendingPathComponent("rotoscope_sound.mp4")
        try? FileManager.default.removeItem(at: outURL)
        guard let session = AVAssetExportSession(asset: comp,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
            return videoURL
        }
        session.outputURL = outURL
        session.outputFileType = .mp4
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }
        return session.status == .completed ? outURL : videoURL
    }

    /// Saves the mp4 into the user's photo library (add-only access).
    private func saveVideoToPhotos(url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photosAccessDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    // MARK: - Helpers

    /// Plain white background for blank flipbook pages.
    private static func whiteImage(size: CGSize) -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let ui = UIImage(cgImage: image)
        guard let data = ui.pngData() else { throw ExportError.encodeFailed }
        try data.write(to: url)
    }

    private func pixelBuffer(from image: CGImage, size: CGSize,
                             context: CIContext,
                             pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height),
                                kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pb)
        }
        guard let buffer = pb else { return nil }
        let ci = CIImage(cgImage: image)
        context.render(ci, to: buffer)
        return buffer
    }

    enum ExportError: LocalizedError {
        case noSource, encodeFailed, photosAccessDenied

        var errorDescription: String? {
            switch self {
            case .noSource: return "동영상이 없어요."
            case .encodeFailed: return "동영상을 만들다가 문제가 생겼어요."
            case .photosAccessDenied:
                return "사진 앱에 저장하려면 설정에서 허용해 주세요."
            }
        }
    }
}
