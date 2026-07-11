import SwiftUI
import YouTubeKit

/// Parent-facing sheet: paste a YouTube link and it opens as a normal tracing
/// project. The UI says "open", but under the hood the clip is cached into
/// the app sandbox — page turns need instant frame seeks and saved projects
/// must reopen offline, which streaming can't provide. Downloading YouTube
/// content can conflict with YouTube's Terms of Service — personal use only.
struct YouTubeImportSheet: View {
    @EnvironmentObject var project: RotoProject
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.red)

            TextField("https://youtube.com/watch?v=…", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(isLoading)

            HStack(spacing: 16) {
                Button {
                    if let s = UIPasteboard.general.string { urlText = s }
                } label: {
                    Label("붙여넣기", systemImage: "doc.on.clipboard")
                        .frame(minWidth: 130, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)

                Button(action: startImport) {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Label("열기", systemImage: "play.fill")
                        }
                    }
                    .frame(minWidth: 130, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading ||
                          urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if isLoading {
                Text("동영상을 여는 중이에요…")
                    .foregroundStyle(.secondary)
            }
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(36)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isLoading)
    }

    private func startImport() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            errorText = "링크가 올바르지 않아요."
            return
        }
        isLoading = true
        errorText = nil

        Task {
            do {
                let local = try await Self.download(youTubeURL: url)
                await MainActor.run {
                    project.load(url: local)
                    isLoading = false
                    dismiss()
                }
                try? FileManager.default.removeItem(at: local)  // load() copied it
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorText = "열지 못했어요. 링크를 확인하고 다시 해보세요."
                }
            }
        }
    }

    /// Resolves the best progressive (video+audio) mp4 stream and downloads
    /// it to a temporary file. 720p is plenty for tracing on the canvas.
    private static func download(youTubeURL: URL) async throws -> URL {
        let streams = try await YouTube(url: youTubeURL).streams
        let candidates = streams
            .filterVideoAndAudio()
            .filter { $0.isNativelyPlayable }
        guard let stream = candidates
            .filter({ ($0.videoResolution ?? 0) <= 720 })
            .highestResolutionStream() ?? candidates.lowestResolutionStream()
        else { throw ImportError.noPlayableStream }

        let (tmp, _) = try await URLSession.shared.download(from: stream.url)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("youtube_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    private enum ImportError: Error { case noPlayableStream }
}
