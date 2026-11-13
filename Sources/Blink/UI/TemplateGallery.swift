import BlinkCore
import SwiftUI

extension TileContent {
    /// The symbol a tile of this kind is shown with.
    var symbolName: String {
        switch self {
        case .web: return "globe"
        case .file(let file): return file.kind == .pdf ? "doc.richtext" : "doc.text"
        case .widget(.clock): return "clock"
        case .widget(.calendar): return "calendar"
        case .widget(.reminders): return "checklist"
        case .widget(.notes): return "note.text"
        case .widget(.messages): return "message"
        }
    }

    /// Each kind of tile has its own colour on a template's map, so a map
    /// reads at a glance: calendar, conversations, what is due, and so on.
    var mapTint: Color {
        switch self {
        case .web: return Color.blinkCool
        case .file: return Color(white: 0.75)
        case .widget(.clock): return Color(red: 0.72, green: 0.62, blue: 1.0)
        case .widget(.calendar): return Color(red: 1.0, green: 0.45, blue: 0.42)
        case .widget(.reminders): return Color(red: 1.0, green: 0.63, blue: 0.27)
        case .widget(.notes): return Color(red: 1.0, green: 0.82, blue: 0.36)
        case .widget(.messages): return Color(red: 0.27, green: 0.86, blue: 0.53)
        }
    }

    /// A word or two for the tile on a template's map.
    var mapLabel: String {
        switch self {
        case .web(let web): return URLInput.displayHost(for: web.url)
        case .file(let file): return file.fileName
        case .widget(let widget): return widget.displayName
        }
    }
}

/// A template drawn small: its columns and tiles, as they will be laid out.
struct TemplateMap: View {
    let template: BoardTemplate

    var body: some View {
        GeometryReader { geometry in
            let canvas = LayoutSize(width: 1400, height: 820)
            let items = template.flowItems
            let frames = FlowLayout.layout(items, in: canvas, options: FlowLayout.Options(gap: 14, minWidth: 180, minHeight: 90))
            // Drawn from the left edge of the first column to the right edge
            // of the last, so the map fills its card.
            let left = frames.values.map(\.minX).min() ?? 0
            let width = max((frames.values.map(\.maxX).max() ?? canvas.width) - left, 1)
            let scale = min(geometry.size.width / width, geometry.size.height / canvas.height)
            let contents = Dictionary(uniqueKeysWithValues: zip(items.map(\.id), template.makeTiles().map(\.content)))
            ZStack(alignment: .topLeading) {
                ForEach(items, id: \.id) { item in
                    if let frame = frames[item.id], let content = contents[item.id] {
                        let tint = content.mapTint
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(tint.opacity(0.26))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(tint.opacity(0.55), lineWidth: 1)
                            )
                            .overlay {
                                VStack(spacing: 3) {
                                    Image(systemName: content.symbolName)
                                        .font(.system(size: 11, weight: .medium))
                                    if frame.height * scale > 34, frame.width * scale > 46 {
                                        Text(content.mapLabel)
                                            .font(.system(size: 8.5, weight: .medium))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                            .padding(.horizontal, 3)
                                    }
                                }
                                .foregroundStyle(Color.white.opacity(0.95))
                            }
                            .frame(width: frame.width * scale, height: frame.height * scale)
                            .offset(x: (frame.x - left) * scale, y: frame.y * scale)
                    }
                }
            }
            // Top-leading, or the tiles would be centred on the largest of them.
            .frame(width: width * scale, height: canvas.height * scale, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Which card of an empty board's gallery is under the pointer. The board
/// samples the pointer and passes it in, since a window in a background app
/// is not reliably told when the pointer moves.
@MainActor
final class GalleryPointer: ObservableObject {
    @Published private(set) var hot: String?
    /// Each card's frame in the gallery and the point it grows from.
    var cards: [String: CardSpot] = [:]

    static let scale: CGFloat = 1.3

    private var lastPointer: CGPoint?

    func update(pointer: CGPoint?) {
        // Only movement counts, so a card picked out some other way stays
        // picked out until the pointer goes somewhere new.
        guard pointer != lastPointer else { return }
        lastPointer = pointer
        guard let pointer else { return set(nil) }
        // The card that has grown keeps the pointer while it is over it,
        // even where it now covers a neighbour.
        if let hot, let card = cards[hot], card.grown.contains(pointer) { return }
        set(cards.first { $0.value.frame.contains(pointer) }?.key)
    }

    /// For the self-check.
    func point(at id: String?) { set(id) }

    private func set(_ id: String?) {
        if hot != id { hot = id }
    }
}

struct CardSpot: Equatable {
    var frame: CGRect
    var anchor: UnitPoint

    var grown: CGRect {
        let width = frame.width * GalleryPointer.scale
        let height = frame.height * GalleryPointer.scale
        return CGRect(
            x: frame.minX + (frame.width - width) * anchor.x,
            y: frame.minY + (frame.height - height) * anchor.y,
            width: width,
            height: height
        )
    }
}

private struct CardSpots: PreferenceKey {
    static let defaultValue: [String: CardSpot] = [:]
    static func reduce(value: inout [String: CardSpot], nextValue: () -> [String: CardSpot]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Shown on an empty board: ready-made boards to start from. Resting on a
/// card magnifies it in place, growing toward the middle so the card stays
/// under the pointer; a click fills the board with it.
struct TemplateGallery: View {
    @ObservedObject var pointer: GalleryPointer
    let onChoose: @MainActor (BoardTemplate) -> Void
    let onAdd: @MainActor () -> Void

    var body: some View {
        GeometryReader { geometry in
            let columns = geometry.size.width >= 940 ? 3 : 2
            let gap: CGFloat = 18
            let cardWidth = min(280, (min(geometry.size.width - 48, 920) - CGFloat(columns - 1) * gap) / CGFloat(columns))
            let all = BoardTemplate.all
            let rows = stride(from: 0, to: all.count, by: columns).map { Array(all[$0..<min($0 + columns, all.count)]) }
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 5) {
                        Text("Start with a template")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Rest on one to look closer. Each is a starting point: move, resize, add or remove anything.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    VStack(spacing: gap) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                            HStack(spacing: gap) {
                                ForEach(Array(row.enumerated()), id: \.element.id) { column, template in
                                    MagnifyingCard(
                                        template: template,
                                        width: cardWidth,
                                        anchor: UnitPoint(
                                            x: column == 0 ? 0 : (column == columns - 1 ? 1 : 0.5),
                                            y: rowIndex == 0 ? 0 : (rowIndex == rows.count - 1 ? 1 : 0.5)
                                        ),
                                        isHot: pointer.hot == template.id,
                                        isDimmed: pointer.hot != nil && pointer.hot != template.id
                                    ) { onChoose(template) }
                                    .zIndex(pointer.hot == template.id ? 1 : 0)
                                }
                            }
                            // A row with a grown card in it goes over the others.
                            .zIndex(row.contains { $0.id == pointer.hot } ? 1 : 0)
                        }
                    }

                    Button(action: onAdd) {
                        Label("Or add a website, widget or file", systemImage: "plus")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(pointer.hot == nil ? 1 : 0.4)
                }
                .padding(.vertical, 30)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
        }
        .coordinateSpace(name: "gallery")
        .onPreferenceChange(CardSpots.self) { spots in
            onMainActor { pointer.cards = spots }
        }
    }
}

private struct MagnifyingCard: View {
    let template: BoardTemplate
    let width: CGFloat
    let anchor: UnitPoint
    let isHot: Bool
    let isDimmed: Bool
    let choose: @MainActor () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 9) {
                TemplateMap(template: template)
                    .padding(8)
                    .frame(height: ((width - 24) * 0.5).rounded())
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if isHot {
                            Text("Use \(template.name)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.85))
                                .padding(.horizontal, 9)
                                .frame(height: 20)
                                .background(Color.blinkAccent, in: Capsule())
                                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                                .padding(7)
                                .transition(.opacity.combined(with: .offset(y: 4)))
                        }
                    }
                HStack(spacing: 6) {
                    Image(systemName: template.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.blinkAccent)
                    Text(template.name)
                        .font(.system(size: 13.5, weight: .semibold))
                }
                Text(template.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(width: width, alignment: .leading)
            .background(
                isHot ? Color(white: 0.12).opacity(0.97) : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isHot ? Color.blinkAccent.opacity(0.45) : Color.white.opacity(0.1), lineWidth: isHot ? 1 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Use the \(template.name) template")
        // A short pause before growing keeps a sweep across the grid calm.
        .scaleEffect(isHot ? GalleryPointer.scale : (isDimmed ? 0.98 : 1), anchor: anchor)
        .shadow(color: .black.opacity(isHot ? 0.5 : 0), radius: isHot ? 28 : 0, y: isHot ? 14 : 0)
        .opacity(isDimmed ? 0.5 : 1)
        .animation(.spring(response: 0.36, dampingFraction: 0.82).delay(isHot ? 0.06 : 0), value: isHot)
        .animation(.easeOut(duration: 0.2), value: isDimmed)
        // Measured outside the magnification, so the frame is where the card sits.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CardSpots.self,
                    value: [template.id: CardSpot(frame: proxy.frame(in: .named("gallery")), anchor: anchor)]
                )
            }
        )
    }
}
