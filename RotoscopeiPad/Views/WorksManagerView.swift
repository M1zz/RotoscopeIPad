import SwiftUI

/// Settings ▸ 작품 정리 and 휴지통: a grown-up picks many works at once.
///
/// 작품 정리 sends them to the trash; the trash brings them back to the home
/// grid or deletes them for good — the only place anything is truly deleted.
/// Both sit behind the grown-up check (settings), so a kid can't do either.
/// Newest first, with the date under each, so old scribbles are easy to find.
struct WorksManagerView: View {
    enum Place { case shelf, trash }
    var place: Place = .shelf

    @State private var works: [URL] = []
    @State private var selected: Set<URL> = []
    @State private var confirmDelete = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]
    private var allSelected: Bool { !works.isEmpty && selected.count == works.count }

    var body: some View {
        Group {
            if works.isEmpty {
                if place == .shelf {
                    ContentUnavailableView("아직 작품이 없어요", systemImage: "square.grid.2x2")
                } else {
                    ContentUnavailableView("휴지통이 비어 있어요", systemImage: "trash")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(works, id: \.self) { dir in
                            WorkTile(dir: dir, isSelected: selected.contains(dir)) {
                                toggle(dir)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(place == .shelf ? Text("작품 정리") : Text("휴지통"))
        .onAppear(perform: reload)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !works.isEmpty {
                    Button(allSelected ? "선택 해제" : "모두 선택") {
                        selected = allSelected ? [] : Set(works)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                VStack(spacing: 10) {
                    if place == .trash {
                        Button { done { RotoProject.restoreFromTrash($0) } } label: {
                            Label("작품 \(selected.count)개 되살리기", systemImage: "arrow.uturn.backward")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button(role: .destructive) {
                        // Off the shelf is only into the trash; from the trash it's for good.
                        if place == .shelf { done { RotoProject.moveToTrash($0) } } else { confirmDelete = true }
                    } label: {
                        Label("작품 \(selected.count)개 지우기", systemImage: "trash")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(16)
                .background(.bar)
            }
        }
        .confirmationDialog("작품 \(selected.count)개를 지울까요?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("지우기", role: .destructive) { done { RotoProject.deleteFromTrash($0) } }
        } message: {
            Text("지운 작품은 되돌릴 수 없어요.")
        }
    }

    private func toggle(_ dir: URL) {
        if selected.contains(dir) { selected.remove(dir) } else { selected.insert(dir) }
    }

    /// Moves or deletes the picked works, then shows what's left.
    private func done(_ action: (Set<URL>) -> Void) {
        action(selected)
        selected = []
        reload()
    }

    private func reload() {
        works = place == .shelf ? RotoProject.listProjects() : RotoProject.listTrash()
    }
}

/// One work: its thumbnail, the day it was last drawn, and a check when picked.
private struct WorkTile: View {
    let dir: URL
    let isSelected: Bool
    let toggle: () -> Void

    private var date: Text? {
        RotoProject.editedAt(dir).map { Text($0, format: .dateTime.year().month().day()) }
    }

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 6) {
                picture
                date?
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("내 작품"))
        .accessibilityValue(date ?? Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var picture: some View {
        let edge: Color = isSelected ? .accentColor : .primary.opacity(0.12)
        return thumbnail
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(edge, lineWidth: isSelected ? 4 : 1))
            .overlay(alignment: .topTrailing) { SelectionMark(isSelected: isSelected).padding(8) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let ui = RotoProject.thumbnail(for: dir) {
            Color.white.overlay(Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill))
        } else {
            Image(systemName: "film")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.12))
        }
    }
}

/// A filled check when picked, an outlined circle when not.
/// Drawings sit on white paper, so the empty circle carries its own backing.
private struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.white, Color.accentColor)
                .background(Circle().fill(Color.accentColor))
        } else {
            Image(systemName: "circle")
                .font(.title)
                .foregroundStyle(.secondary)
                .background(Circle().fill(.white.opacity(0.85)))
        }
    }
}
