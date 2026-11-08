import PhotosUI
import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Pictures a grown-up brings in (from Photos or Files). Each one shows on
/// the home grid as a way to start a sketchbook: the picture sits on the
/// page, and the kid draws over it.
enum PictureLibrary {
    /// Settings: lay new pictures down faded, so the kid's lines stand out.
    static let fadedKey = "picturesFaded"
    /// How faint a faded picture is.
    static let fadedOpacity = 0.4

    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pictures", isDirectory: true)
    }

    /// Newest first.
    static func list() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.creationDateKey])) ?? []
        func added(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }
        return files.filter { $0.pathExtension == "jpg" }.sorted { added($0) > added($1) }
    }

    /// Saves a picture no bigger than a page (long side 1600).
    static func add(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        let scale = min(1, RotoProject.blankCanvasSize.width / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(),
                          height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let page = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? page.jpegData(compressionQuality: 0.9)?
            .write(to: root.appendingPathComponent(UUID().uuidString + ".jpg"))
        thumbnails.removeAllObjects()
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Small decoded copies for the home grid.
    private static let thumbnails = NSCache<NSURL, UIImage>()

    static func thumbnail(_ url: URL) -> UIImage? {
        if let hit = thumbnails.object(forKey: url as NSURL) { return hit }
        guard let image = UIImage(contentsOfFile: url.path)?
            .preparingThumbnail(of: CGSize(width: 480, height: 480)) else { return nil }
        thumbnails.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Settings ▸ 그리기 ▸ 그림 넣기: add pictures from Photos or Files, take
/// them off, and choose whether they lie faded under the drawing.
struct PicturesView: View {
    @AppStorage(PictureLibrary.fadedKey) private var faded = true
    @State private var pictures = PictureLibrary.list()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importingFiles = false
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        List {
            Section {
                Toggle("흐리게 깔기", isOn: $faded)
            } footer: {
                Text("넣은 그림은 홈 화면에 나와요. 아이가 고르면 그 그림 위에 그려요. 흐리게 깔면 아이가 그린 선이 더 잘 보여요.")
            }
            Section {
                PhotosPicker(selection: $photoItems, matching: .images) {
                    Label("사진에서 넣기", systemImage: "photo.on.rectangle")
                }
                Button { importingFiles = true } label: {
                    Label("파일에서 넣기", systemImage: "folder")
                }
            }
            Section {
                if pictures.isEmpty {
                    Text("아직 넣은 그림이 없어요")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(pictures, id: \.self) { tile($0) }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("그림 넣기")
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        PictureLibrary.add(data)
                    }
                }
                photoItems = []
                reload()
            }
        }
        .fileImporter(isPresented: $importingFiles, allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            for url in (try? result.get()) ?? [] {
                let open = url.startAccessingSecurityScopedResource()
                if let data = try? Data(contentsOf: url) { PictureLibrary.add(data) }
                if open { url.stopAccessingSecurityScopedResource() }
            }
            reload()
        }
    }

    private func tile(_ url: URL) -> some View {
        Color.white
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let image = PictureLibrary.thumbnail(url) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .opacity(faded ? PictureLibrary.fadedOpacity : 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12)))
            .overlay(alignment: .topTrailing) {
                Button {
                    PictureLibrary.remove(url)
                    reload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .red)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("지우기"))
            }
    }

    private func reload() {
        pictures = PictureLibrary.list()
        NotificationCenter.default.post(name: RotoProject.projectsDidChange, object: nil)
    }
}
