import SwiftUI

/// Icon-only home grid: a big ➕ to start a new project, then a card per
/// saved project showing its drawing. Tap a card to keep working on it.
struct HomeView: View {
    @EnvironmentObject var project: RotoProject
    @State private var projects: [URL] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 20)],
                      spacing: 20) {
                // Shoot a new video and draw on it right away.
                if CameraVideoPicker.isAvailable {
                    Button { project.showCameraPicker = true } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 44))
                            Image(systemName: "plus")
                                .font(.system(size: 28, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }

                // New project from a video.
                Button { project.showPhotoPicker = true } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 44))
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                // New blank flipbook (white pages, no video).
                Button { project.createBlank() } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "pencil.and.outline")
                            .font(.system(size: 44))
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                ForEach(projects, id: \.self) { dir in
                    Button { project.openProject(at: dir) } label: {
                        thumbnail(for: dir)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        // Long-press → red trash to delete.
                        Button(role: .destructive) {
                            RotoProject.deleteProject(at: dir)
                            projects = RotoProject.listProjects()
                        } label: {
                            Label("지우기", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear { projects = RotoProject.listProjects() }
        .fullScreenCover(isPresented: $project.showCameraPicker) {
            CameraVideoPicker(isPresented: $project.showCameraPicker,
                              onPick: { url in project.load(url: url) })
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func thumbnail(for dir: URL) -> some View {
        let thumbPath = dir.appendingPathComponent("thumb.png").path
        Group {
            if let ui = UIImage(contentsOfFile: thumbPath) {
                Color.clear
                    .frame(height: 160)
                    .overlay(
                        Image(uiImage: ui)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
            } else {
                Image(systemName: "film")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(Color.gray.opacity(0.12))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
