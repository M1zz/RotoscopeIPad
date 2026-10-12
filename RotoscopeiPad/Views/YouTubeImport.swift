import SwiftUI
#if DEBUG
import YouTubeKit
#endif

/// Parent-facing sheet: paste a video link and it opens as a normal tracing
/// project. The link is fetched as a direct video file. The UI says "open",
/// but the clip is cached into the app sandbox — page turns need instant
/// frame seeks and saved projects must reopen offline, which streaming can't
/// provide.
///
/// YouTube links resolve only in Debug builds (running from Xcode).
/// Downloading YouTube content conflicts with YouTube's ToS and App Review
/// 5.2.3, so Release builds — TestFlight and the App Store — compile it out
/// entirely, with no hidden switch to turn it back on (that would be 2.3.1).
struct VideoLinkImportSheet: View {
    @EnvironmentObject var project: RotoProject
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.indigo)

            TextField("https://…", text: $urlText)
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
                let local = try await Self.download(videoURL: url)
                // load() copies the file into the project; hasVideo tells us
                // whether the downloaded data was actually a decodable video.
                let opened = await MainActor.run { () -> Bool in
                    project.load(url: local)
                    return project.hasVideo
                }
                try? FileManager.default.removeItem(at: local)
                await MainActor.run {
                    isLoading = false
                    if opened {
                        dismiss()
                    } else {
                        errorText = "열지 못했어요. 동영상 링크인지 확인해 주세요."
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorText = "열지 못했어요. 링크를 확인하고 다시 해보세요."
                }
            }
        }
    }

    /// Fetches the link into a temporary file, treating it as a direct
    /// video file URL. Debug builds first try it as a YouTube link.
    private static func download(videoURL: URL) async throws -> URL {
        #if DEBUG
        if let streamURL = try? await youTubeStreamURL(for: videoURL) {
            return try await fetch(streamURL, ext: "mp4")
        }
        #endif
        let ext = videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension
        return try await fetch(videoURL, ext: ext)
    }

    #if DEBUG
    /// Best progressive mp4 (≤720p — plenty for tracing). Debug only.
    private static func youTubeStreamURL(for url: URL) async throws -> URL? {
        let streams = try await YouTube(url: url).streams
        let candidates = streams
            .filterVideoAndAudio()
            .filter { $0.isNativelyPlayable }
        let stream = candidates
            .filter { ($0.videoResolution ?? 0) <= 720 }
            .highestResolutionStream() ?? candidates.lowestResolutionStream()
        return stream?.url
    }
    #endif

    private static func fetch(_ remote: URL, ext: String) async throws -> URL {
        let (tmp, _) = try await URLSession.shared.download(from: remote)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("import_\(UUID().uuidString).\(ext)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}
