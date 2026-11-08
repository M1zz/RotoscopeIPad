import SwiftUI

/// Settings ▸ 그리기 ▸ 도장 고르기: a grown-up picks which stamps the kid
/// sees, up to `StampShape.limit`, from shapes, animals and things.
struct StampPickerView: View {
    @AppStorage(StampShape.storageKey) private var stampIDs = StampShape.starterIDs

    private var picked: [StampShape] { StampShape.chosen(stampIDs) }
    private var isFull: Bool { picked.count >= StampShape.limit }
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("아이 화면에는 고른 도장만 나와요. 10개까지 고를 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(StampShape.Kind.allCases, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: 10) {
                        kind.title.font(.headline)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(StampShape.allCases.filter { $0.kind == kind }) { tile($0) }
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("도장 고르기")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text(verbatim: "\(picked.count) / \(StampShape.limit)")
                    .monospacedDigit()
                    .foregroundStyle(isFull ? .orange : .secondary)
            }
        }
    }

    private func tile(_ shape: StampShape) -> some View {
        let on = picked.contains(shape)
        // Full: the rest wait until one is taken off.
        let blocked = !on && isFull
        return Button { toggle(shape) } label: {
            StampGlyph(shape: shape, colorHex: "000000")
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(on ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(on ? Color.accentColor : .clear, lineWidth: 3))
                .overlay(alignment: .topTrailing) {
                    if on {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                    }
                }
                .opacity(blocked ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .accessibilityLabel(shape.accessibilityName)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ shape: StampShape) {
        var ids = picked.map(\.rawValue)
        if let i = ids.firstIndex(of: shape.rawValue) {
            ids.remove(at: i)
        } else if !isFull {
            ids.append(shape.rawValue)
        }
        stampIDs = ids.joined(separator: ",")
    }
}

private extension StampShape.Kind {
    var title: Text {
        switch self {
        case .shapes:  return Text("도형")
        case .animals: return Text("동물")
        case .things:  return Text("물건")
        }
    }
}

/// A stamp drawn from its real pieces in the pen color, so a button shows
/// exactly what lands on the page. A faint shadow keeps white visible.
struct StampGlyph: View {
    let shape: StampShape
    let colorHex: String

    var body: some View {
        ZStack {
            ForEach(shape.parts.indices, id: \.self) { i in
                Piece(part: shape.parts[i]).fill(Color(rgbHex: colorHex))
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 0.6)
    }

    private struct Piece: Shape {
        let part: StampPart

        func path(in rect: CGRect) -> Path {
            let r = min(rect.width, rect.height) / 2
            let points = part.points.map {
                CGPoint(x: rect.midX + $0.x * r, y: rect.midY + $0.y * r)
            }
            return Path(StrokeGeometry.path(points: points, closed: true, smooth: part.smooth))
        }
    }
}

extension StampShape {
    /// Spoken name for VoiceOver (the stamp buttons are pictures only).
    var accessibilityName: Text {
        switch self {
        case .circle:    return Text("동그라미 도장")
        case .square:    return Text("네모 도장")
        case .triangle:  return Text("세모 도장")
        case .heart:     return Text("하트 도장")
        case .star:      return Text("별 도장")
        case .diamond:   return Text("마름모 도장")
        case .moon:      return Text("달 도장")
        case .drop:      return Text("물방울 도장")
        case .cloud:     return Text("구름 도장")
        case .flower:    return Text("꽃 도장")
        case .cat:       return Text("고양이 도장")
        case .bear:      return Text("곰 도장")
        case .rabbit:    return Text("토끼 도장")
        case .fish:      return Text("물고기 도장")
        case .bird:      return Text("새 도장")
        case .butterfly: return Text("나비 도장")
        case .house:     return Text("집 도장")
        case .tree:      return Text("나무 도장")
        case .car:       return Text("자동차 도장")
        case .rocket:    return Text("로켓 도장")
        case .sun:       return Text("해 도장")
        case .iceCream:  return Text("아이스크림 도장")
        }
    }
}
