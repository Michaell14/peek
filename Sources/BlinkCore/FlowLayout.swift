import Foundation

/// The edge or corner of a tile being dragged to resize it.
public enum ResizeHandle: CaseIterable, Sendable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    public var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    public var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
    public var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
    public var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
}

/// Tiles stand in columns, side by side. A column is a stack of one or more
/// tiles, top to bottom. A tile keeps the height it was given; one without a
/// height fills what its column has left. The row of columns is centred, and
/// squeezed if it is too wide.
public enum FlowLayout {
    public struct Item: Hashable, Sendable {
        public var id: UUID
        public var width: Double
        /// nil fills what is left of the column.
        public var height: Double?
        /// Neighbouring items with the same column are stacked in it.
        public var column: UUID

        public init(id: UUID, width: Double, height: Double?, column: UUID = UUID()) {
            self.id = id
            self.width = width
            self.height = height
            self.column = column
        }
    }

    public struct Options: Hashable, Sendable {
        public var gap: Double
        /// The narrowest a tile may be made by resizing.
        public var minWidth: Double
        /// The shortest a tile is ever drawn.
        public var minHeight: Double

        public init(gap: Double = 12, minWidth: Double = 160, minHeight: Double = 80) {
            self.gap = gap
            self.minWidth = minWidth
            self.minHeight = minHeight
        }
    }

    /// The columns, left to right: runs of neighbouring items that share a column.
    public static func columns(for items: [Item]) -> [[Item]] {
        var columns: [[Item]] = []
        for item in items {
            if let last = columns.last?.last, last.column == item.column {
                columns[columns.count - 1].append(item)
            } else {
                columns.append([item])
            }
        }
        return columns
    }

    /// The heights of one column's tiles, top to bottom. Tiles keep their own
    /// heights and tiles without one share what is left. A column that holds
    /// more than fits has its tiles give way in proportion.
    public static func heights(for column: [Item], available: Double, options: Options = Options()) -> [Double] {
        guard !column.isEmpty else { return [] }
        let room = max(available - options.gap * Double(column.count - 1), 0)
        let fills = column.filter { $0.height == nil }.count
        var own = column.map { item in item.height.map { min(max($0, options.minHeight), available) } }
        let ownTotal = own.compactMap { $0 }.reduce(0, +)
        let fillFloor = min(Double(fills) * options.minHeight, room)
        if ownTotal + fillFloor > room, ownTotal > 0 {
            let scale = max(room - fillFloor, 0) / ownTotal
            own = own.map { $0.map { $0 * scale } }
        }
        let used = own.compactMap { $0 }.reduce(0, +)
        let share = fills > 0 ? max(room - used, 0) / Double(fills) : 0
        return own.map { $0 ?? share }
    }

    /// Frames in points, relative to the canvas origin.
    ///
    /// - Parameter originX: where the row starts, instead of centred. Used
    ///   while a tile is dragged, so the columns being aimed at stay put.
    public static func layout(
        _ items: [Item],
        in canvas: LayoutSize,
        options: Options = Options(),
        originX: Double? = nil
    ) -> [UUID: LayoutRect] {
        guard !items.isEmpty, canvas.width > 0, canvas.height > 0 else { return [:] }

        let columns = columns(for: items)
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
        let slack = max(canvas.width - total, 0)
        var x = originX.map { min(max($0, 0), slack) } ?? slack / 2
        var frames: [UUID: LayoutRect] = [:]

        for (column, width) in zip(columns, widths) {
            var y = 0.0
            for (item, height) in zip(column, heights(for: column, available: canvas.height, options: options)) {
                frames[item.id] = LayoutRect(x: x, y: y, width: width, height: height).integral
                y += height + options.gap
            }
            x += width + options.gap
        }
        return frames
    }

    /// The tallest `id` can be made while its column still fits: the others
    /// in it keep their heights, and tiles that fill give way down to the
    /// shortest a tile is drawn.
    public static func maxHeight(
        of id: UUID,
        in items: [Item],
        canvasHeight: Double,
        options: Options = Options()
    ) -> Double {
        guard let column = columns(for: items).first(where: { $0.contains { $0.id == id } }) else { return canvasHeight }
        let others = column.filter { $0.id != id }
        let taken = others.reduce(0) { $0 + max($1.height ?? options.minHeight, options.minHeight) }
        return max(canvasHeight - taken - options.gap * Double(column.count - 1), options.minHeight)
    }

    /// The arrangement if the tile `id`, being dragged, were let go at
    /// `point`. `items` is the arrangement shown now, dragged tile included.
    ///
    /// - Over the middle of a column, the tile joins its stack: above the
    ///   tile under the pointer if the pointer is in its top half, below it
    ///   otherwise, and at the bottom when below the last tile. It takes the
    ///   column's width.
    /// - Near a column's left or right edge, between columns, or past either
    ///   end of the row, it becomes a column of its own there.
    /// - Over the place it already has, nothing changes, so the arrangement
    ///   does not flicker as tiles make room.
    public static func dropping(
        _ id: UUID,
        at point: LayoutPoint,
        items: [Item],
        in canvas: LayoutSize,
        options: Options = Options(),
        originX: Double? = nil
    ) -> [Item] {
        guard var moving = items.first(where: { $0.id == id }) else { return items }
        let frames = layout(items, in: canvas, options: options, originX: originX)
        if let own = frames[id], own.contains(point) { return items }

        var columns = columns(for: items.filter { $0.id != id })
        guard !columns.isEmpty else { return items }
        let spans = columns.map { column -> (minX: Double, maxX: Double) in
            let rects = column.compactMap { frames[$0.id] }
            return (rects.map(\.minX).min() ?? 0, rects.map(\.maxX).max() ?? 0)
        }

        func ownColumn(at index: Int) -> [Item] {
            // A tile already standing alone keeps its column, so letting go
            // where it already is changes nothing.
            if columns.contains(where: { $0.contains { $0.column == moving.column } }) {
                moving.column = UUID()
            }
            columns.insert([moving], at: index)
            return columns.flatMap { $0 }
        }

        for (index, span) in spans.enumerated() where point.x >= span.minX && point.x <= span.maxX {
            let edge = min(max((span.maxX - span.minX) * 0.2, 24), 64)
            if point.x < span.minX + edge { return ownColumn(at: index) }
            if point.x > span.maxX - edge { return ownColumn(at: index + 1) }

            let column = columns[index]
            let position = column.firstIndex { (frames[$0.id]?.midY ?? 0) > point.y } ?? column.count
            moving.column = column[0].column
            moving.width = column.map(\.width).max() ?? moving.width
            columns[index].insert(moving, at: position)
            return columns.flatMap { $0 }
        }
        // Between two columns, or past either end of the row.
        return ownColumn(at: spans.firstIndex { point.x < $0.minX } ?? spans.count)
    }

    /// Reads an arrangement back out of tile positions: which tiles share a
    /// column, in what order, and how big each is. Laying the result out
    /// again reproduces the positions it was read from. Boards saved in the
    /// old Freeform mode become columns this way.
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
            let columnID = UUID()
            let stack = column.sorted { $0.rect.y < $1.rect.y }
            for (index, tile) in stack.enumerated() {
                // The bottom tile of a column that reaches the bottom of the
                // canvas was filling it.
                let fills = index == stack.count - 1 && tile.rect.maxY >= canvasHeight - 1.5
                items.append(Item(
                    id: tile.id,
                    width: tile.rect.width,
                    height: fills ? nil : max(tile.rect.height, options.minHeight),
                    column: columnID
                ))
            }
        }
        return items
    }
}
