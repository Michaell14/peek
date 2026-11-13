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
                        let isWidget: Bool = { if case .widget = content { return true } else { return false } }()
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isWidget ? Color.white.opacity(0.13) : Color.blinkCool.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
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
                                .foregroundStyle(Color.white.opacity(0.8))
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

/// Shown on an empty board: ready-made boards to start from.
struct TemplateGallery: View {
    let onChoose: @MainActor (BoardTemplate) -> Void
    let onAdd: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 5) {
                    Text("Start with a template")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Each one is a starting point: move, resize, add or remove anything afterwards.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 280), spacing: 14)], spacing: 14) {
                    ForEach(BoardTemplate.all) { template in
                        TemplateCard(template: template) { onChoose(template) }
                    }
                }
                .frame(maxWidth: 900)

                Button(action: onAdd) {
                    Label("Or add a website, widget or file", systemImage: "plus")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

private struct TemplateCard: View {
    let template: BoardTemplate
    let choose: @MainActor () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 10) {
                TemplateMap(template: template)
                    .frame(height: 112)
                    .padding(8)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
            .background(
                Color.white.opacity(isHovering ? 0.1 : 0.05),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovering ? 0.22 : 0.1), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Use the \(template.name) template")
    }
}
