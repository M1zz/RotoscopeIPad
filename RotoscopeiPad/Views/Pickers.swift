import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

/// In-app camera for shooting a video to draw on ("찍고 → 바로 그리기").
struct CameraVideoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (URL) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 30   // short clips: kids draw every scene
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {
        let parent: CameraVideoPicker
        init(_ parent: CameraVideoPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.isPresented = false
            guard let url = info[.mediaURL] as? URL else { return }
            // Stage a copy: the capture temp file may vanish after dismissal.
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("CameraImport-\(UUID().uuidString)", isDirectory: true)
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: dest)
            } catch { return }
            let onPick = parent.onPick
            DispatchQueue.main.async { onPick(dest) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

/// Photo-library picker for choosing a video (PHPicker: runs out of process,
/// so no photo-library permission prompt is needed).
struct PhotosVideoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (URL) -> Void
    /// Progress / error messages for the status bar.
    var onStatus: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotosVideoPicker
        init(_ parent: PhotosVideoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController,
                    didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            guard let provider = results.first?.itemProvider else { return } // cancelled
            guard provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                parent.onStatus("동영상이 아니에요. 동영상을 골라 주세요!")
                return
            }

            // Large / iCloud videos can take a while to materialize.
            parent.onStatus("사진에서 가져오는 중… 조금만 기다려요!")
            let onPick = parent.onPick
            let onStatus = parent.onStatus
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                // The URL is only valid inside this callback — copy out first.
                // Copy into a unique subdirectory: RotoProject.load() copies to
                // tmp/<name> itself, so landing on that exact path would make
                // its remove-then-copy delete the source.
                guard let url else {
                    let reason = error?.localizedDescription ?? "알 수 없는 문제"
                    DispatchQueue.main.async { onStatus("동영상을 가져오지 못했어요: \(reason)") }
                    return
                }
                do {
                    let dir = FileManager.default.temporaryDirectory
                        .appendingPathComponent("PhotosImport-\(UUID().uuidString)",
                                                isDirectory: true)
                    try FileManager.default.createDirectory(at: dir,
                                                            withIntermediateDirectories: true)
                    let dest = dir.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: dest)
                    DispatchQueue.main.async { onPick(dest) }
                } catch {
                    let reason = error.localizedDescription
                    DispatchQueue.main.async { onStatus("동영상을 가져오지 못했어요: \(reason)") }
                }
            }
        }
    }
}

/// Document picker for choosing a video file (Files app, iCloud Drive, etc.).
struct VideoDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie, .video]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}

/// UIActivityViewController wrapper to share/export the result folder.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
