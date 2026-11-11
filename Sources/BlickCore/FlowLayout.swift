import Foundation

/// Flow mode: tiles are packed, in order, into columns that fill the height of
/// the canvas. Short tiles stack; a tile with no height of its own takes a
/// whole column. The row of columns is centred, and squeezed if it is too wide.
public enum FlowLayout {
    public struct Item: Hashable, Sendable {
        public var id: UUID
        public var width: Double
        /// nil means "fill the column".
        public var height: Double?

        public init(id: UUID, width: Double, height: Double?) {
            self.id = id
            self.width = width
            self.height = height
        }
    }

    public struct Options: Hashable, Sendable {
        public var gap: Double
        /// The narrowest a tile may be made by resizing.
        public var minWidth: Double
        /// The shortest a stacked tile is ever drawn.
        public var minHeight: Double

        public init(gap: Double = 12, minWidth: Double = 160, minHeight: Double = 80) {
            self.gap = gap
            self.minWidth = minWidth
            self.minHeight = minHeight
        }
    }

    /// Groups items into columns without assigning positions.
    public static func columns(for items: [Item], availableHeight: Double, options: Options = Options()) -> [[Item]] {
        var columns: [[Item]] = []
        var used = 0.0
        var currentFills = false

        for item in items {
            guard let wanted = item.height else {
                columns.append([item])
                currentFills = true
                used = availableHeight
                continue
            }
            let height = min(max(wanted, options.minHeight), availableHeight)
            if !columns.isEmpty, !currentFills, used + options.gap + height <= availableHeight + 0.5 {
                columns[columns.count - 1].append(item)
                used += options.gap + height
            } else {
                columns.append([item])
                currentFills = false
                used = height
            }
        }
        return columns
    }

    /// Frames in points, relative to the canvas origin.
    public static func layout(_ items: [Item], in canvas: LayoutSize, options: Options = Options()) -> [UUID: LayoutRect] {
        guard !items.isEmpty, canvas.width > 0, canvas.height > 0 else { return [:] }

        let columns = columns(for: items, availableHeight: canvas.height, options: options)
        // Widths are taken as given. `minWidth` limits what a person can drag
        // a tile down to; it must not re-inflate columns that were squeezed
        // to fit, or reading a layout back and laying it out again would not
        // land in the same place.
        var widths = columns.map { column in
            max(1, column.map(\.width).max() ?? 1)
        }

        let gaps = options.gap * Double(columns.count - 1)
        let natural = widths.reduce(0, +)
        let room = max(canvas.width - gaps, 1)
        if natural > room {
            let scale = room / natural
            widths = widths.map { $0 * scale }
        }

        let total = widths.reduce(0, +) + gaps
        var x = max(0, (canvas.width - total) / 2)
        var frames: [UUID: LayoutRect] = [:]

        for (column, width) in zip(columns, widths) {
            var y = 0.0
            for (index, item) in column.enumerated() {
                let isLast = index == column.count - 1
                let height: Double
                if isLast {
                    // The last tile soaks up whatever is left so every column
                    // ends on the same line.
                    height = max(canvas.height - y, 0)
                } else {
                    height = min(max(item.height ?? canvas.height, options.minHeight), canvas.height)
                }
                frames[item.id] = LayoutRect(x: x, y: y, width: width, height: height).integral
                y += height + options.gap
            }
            x += width + options.gap
        }
        return frames
    }

    /// Reads a flow arrangement back out of tile positions: which tiles share
    /// a column, in what order, and how big each wants to be. Laying the
    /// result out again reproduces the positions it was read from, which is
    /// what lets a board switch to freeform and back without reshuffling.
    public static func items(
        from frames: [(id: UUID, rect: LayoutRect)],
        canvasHeight: Double,
        options: Options = Options()
    ) -> [Item] {
        // Tiles that overlap horizontally by at least half belong together.
        var columns: [[(id: UUID, rect: LayoutRect)]] = []
        for frame in frames.sorted(by: { ($0.rect.x, $0.rect.y) < ($1.rect.x, $1.rect.y) }) {
            if let anchor = columns.last?.first?.rect {
                let shared = min(anchor.maxX, frame.rect.maxX) - max(anchor.minX, frame.rect.minX)
                if shared >= 0.5 * min(anchor.width, frame.rect.width) {
                    columns[columns.count - 1].append(frame)
                    continue
                }
            }
            columns.append([frame])
        }

        var items: [Item] = []
        for column in columns {
            let stack = column.sorted { $0.rect.y < $1.rect.y }
            var used = 0.0
            for (index, tile) in stack.enumerated() {
                var height: Double? = max(tile.rect.height, options.minHeight)
                if stack.count == 1 {
                    // A tall tile on its own was filling its column.
                    if tile.rect.height >= canvasHeight * 0.7 { height = nil }
                } else if index == stack.count - 1 {
                    // The last tile of a stack is stretched to the bottom, so
                    // its drawn height says nothing about the height it
                    // asked for. Any height that fits keeps the stack whole.
                    let room = canvasHeight - used - 1
                    height = min(tile.rect.height, max(room, options.minHeight))
                }
                if let height { used += height + options.gap }
                items.append(Item(id: tile.id, width: tile.rect.width, height: height))
            }
        }
        return items
    }

    /// Where a dragged tile would land if dropped at `point`: an index into the
    /// item list with the dragged tile removed.
    public static func insertionIndex(
        at point: LayoutPoint,
        moving: UUID,
        items: [Item],
        in canvas: LayoutSize,
        options: Options = Options()
    ) -> Int {
        let others = items.filter { $0.id != moving }
        guard !others.isEmpty else { return 0 }

        let frames = layout(others, in: canvas, options: options)
        let columns = columns(for: others, availableHeight: canvas.height, options: options)

        var best: (index: Int, distance: Double)?
        for (index, item) in others.enumerated() {
            guard let frame = frames[item.id] else { continue }
            let distance = frame.distance(to: point)
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        guard let nearest = best, let frame = frames[others[nearest.index].id] else { return others.count }

        let stacked = columns.first { $0.contains { $0.id == others[nearest.index].id } }.map { $0.count > 1 } ?? false
        let after = stacked ? point.y > frame.midY : point.x > frame.midX
        return nearest.index + (after ? 1 : 0)
    }
}
