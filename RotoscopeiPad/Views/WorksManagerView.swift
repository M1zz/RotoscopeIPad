import SwiftUI

/// Settings ▸ 작품 정리: a grown-up picks many works at once and deletes them.
///
/// Kids make a lot of flipbooks and the home grid fills up fast; one-by-one
/// long-press deleting forty of them is a chore. This page sits behind the
/// grown-up check (settings), so a kid can't clear the shelf by accident.
/// Newest first, with the date under each, so old scribbles are easy to find.
struct WorksManagerView: View {
    @State private var works: [URL] = RotoProject.listProjects()
    @State private var selected: Set<URL> = []
    @State private var confirmDelete = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]
    private var allSelected: Bool { !works.isEmpty && selected.count == works.count }

    var body: some View {
        Group {
            if works.isEmpty {
                ContentUnavailableView("아직 작품이 없어요", systemImage: "square.grid.2x2")
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
        .navigationTitle("작품 정리")
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
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("작품 \(selected.count)개 지우기", systemImage: "trash")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(16)
                .background(.bar)
            }
        }
        .confirmationDialog("작품 \(selected.count)개를 지울까요?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("지우기", role: .destructive, action: deleteSelected)
        } message: {
            Text("지운 작품은 되돌릴 수 없어요.")
        }
    }

    private func toggle(_ dir: URL) {
        if selected.contains(dir) { selected.remove(dir) } else { selected.insert(dir) }
    }

    private func deleteSelected() {
        for dir in selected { RotoProject.deleteProject(at: dir) }
        selected = []
        works = RotoProject.listProjects()
    }
}

/// One work: its thumbnail, the day it was last drawn, and a check when picked.
private struct WorkTile: View {
    let dir: URL
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 6) {
                thumbnail
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                      lineWidth: isSelected ? 4 : 1))
                    .overlay(alignment: .topTrailing) {
                        // Drawings sit on white paper, so the empty circle needs its own outline.
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title)
                            .foregroundStyle(isSelected ? Color.white : Color.secondary,
                                             Color.accentColor)
                            .background(Circle().fill(isSelected ? Color.accentColor : Color.white.opacity(0.85)))
                            .padding(8)
                    }
                if let date = RotoProject.editedAt(dir) {
                    Text(date, format: .dateTime.year().month().day())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("내 작품"))
        .accessibilityValue(RotoProject.editedAt(dir).map {
            Text($0, format: .dateTime.year().month().day())
        } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let ui = UIImage(contentsOfFile: dir.appendingPathComponent("thumb.png").path) {
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
