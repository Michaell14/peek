import Foundation

public enum ResizeHandle: CaseIterable, Sendable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    public var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    public var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
    public var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
    public var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
}

/// An alignment line to draw while a tile snaps to it.
public struct Guide: Hashable, Sendable {
    public enum Axis: Sendable {
        /// A vertical line at x = position.
        case vertical
        /// A horizontal line at y = position.
        case horizontal
    }

    public var axis: Axis
    public var position: Double

    public init(axis: Axis, position: Double) {
        self.axis = axis
        self.position = position
    }
}

public struct SnapOptions: Hashable, Sendable {
    public var isEnabled: Bool
    /// How close, in points, an edge must be before it jumps to a guide.
    public var threshold: Double
    /// Breathing room kept between neighbouring tiles.
    public var gap: Double

    public init(isEnabled: Bool = true, threshold: Double = 8, gap: Double = 12) {
        self.isEnabled = isEnabled
        self.threshold = threshold
        self.gap = gap
    }
}

/// Freeform mode: dragging and resizing tiles on an open canvas. Everything
/// here works in points relative to the canvas origin.
public enum FreeformLayout {
    public struct Result: Hashable, Sendable {
        public var rect: Rect
        public var guides: [Guide]
    }

    public static func move(
        _ original: Rect,
        by delta: Point,
        in canvas: Size,
        others: [Rect],
        snap: SnapOptions = SnapOptions()
    ) -> Result {
        var rect = original.offsetBy(dx: delta.x, dy: delta.y)
        var guides: [Guide] = []

        if snap.isEnabled {
            let x = snapLines(.vertical, canvas: canvas, others: others, gap: snap.gap)
            if let hit = nearest(
                [(rect.minX, x.edges), (rect.maxX, x.edges), (rect.midX, x.centers)],
                threshold: snap.threshold
            ) {
                rect.x += hit.adjustment
                guides.append(Guide(axis: .vertical, position: hit.line))
            }
            let y = snapLines(.horizontal, canvas: canvas, others: others, gap: snap.gap)
            if let hit = nearest(
                [(rect.minY, y.edges), (rect.maxY, y.edges), (rect.midY, y.centers)],
                threshold: snap.threshold
            ) {
                rect.y += hit.adjustment
                guides.append(Guide(axis: .horizontal, position: hit.line))
            }
        }

        return Result(rect: clamp(rect, to: canvas), guides: guides)
    }

    public static func resize(
        _ original: Rect,
        handle: ResizeHandle,
        by delta: Point,
        in canvas: Size,
        others: [Rect],
        snap: SnapOptions = SnapOptions(),
        minSize: Size = Size(width: 160, height: 100)
    ) -> Result {
        var left = original.minX
        var right = original.maxX
        var top = original.minY
        var bottom = original.maxY
        var guides: [Guide] = []

        let xLines = snap.isEnabled ? snapLines(.vertical, canvas: canvas, others: others, gap: snap.gap).edges : []
        let yLines = snap.isEnabled ? snapLines(.horizontal, canvas: canvas, others: others, gap: snap.gap).edges : []

        func snapped(_ value: Double, _ lines: [Double], _ axis: Guide.Axis) -> Double {
            guard let hit = nearest([(value, lines)], threshold: snap.threshold) else { return value }
            guides.append(Guide(axis: axis, position: hit.line))
            return value + hit.adjustment
        }

        if handle.movesLeft {
            left = snapped(left + delta.x, xLines, .vertical)
            left = min(max(left, 0), right - minSize.width)
        }
        if handle.movesRight {
            right = snapped(right + delta.x, xLines, .vertical)
            right = max(min(right, canvas.width), left + minSize.width)
        }
        if handle.movesTop {
            top = snapped(top + delta.y, yLines, .horizontal)
            top = min(max(top, 0), bottom - minSize.height)
        }
        if handle.movesBottom {
            bottom = snapped(bottom + delta.y, yLines, .horizontal)
            bottom = max(min(bottom, canvas.height), top + minSize.height)
        }

        return Result(
            rect: Rect(x: left, y: top, width: right - left, height: bottom - top),
            guides: guides
        )
    }

    /// Keeps a rect inside the canvas, shrinking it only if it cannot fit.
    public static func clamp(_ rect: Rect, to canvas: Size) -> Rect {
        var result = rect
        result.width = min(result.width, canvas.width)
        result.height = min(result.height, canvas.height)
        result.x = min(max(result.x, 0), canvas.width - result.width)
        result.y = min(max(result.y, 0), canvas.height - result.height)
        return result
    }

    /// Finds room for a new tile: the first spot (reading left to right, top to
    /// bottom) that touches nothing, or failing that the least crowded one.
    public static func placeNew(
        size: Size,
        in canvas: Size,
        existing: [Rect],
        gap: Double = 12,
        step: Double = 24
    ) -> Rect {
        let width = min(size.width, canvas.width)
        let height = min(size.height, canvas.height)
        guard !existing.isEmpty else {
            return Rect(x: 0, y: 0, width: width, height: height)
        }

        let padded = existing.map { $0.insetBy(dx: -gap, dy: -gap) }
        var best = Rect(x: 0, y: 0, width: width, height: height)
        var bestOverlap = Double.infinity

        var y = 0.0
        while y <= canvas.height - height + 0.5 {
            var x = 0.0
            while x <= canvas.width - width + 0.5 {
                let candidate = Rect(x: x, y: y, width: width, height: height)
                let overlap = padded.reduce(0) { $0 + candidate.overlapArea(with: $1) }
                if overlap == 0 { return candidate }
                if overlap < bestOverlap {
                    bestOverlap = overlap
                    best = candidate
                }
                x += step
            }
            y += step
        }
        return best
    }

    // MARK: - Snapping

    private static func snapLines(
        _ axis: Guide.Axis,
        canvas: Size,
        others: [Rect],
        gap: Double
    ) -> (edges: [Double], centers: [Double]) {
        let extent = axis == .vertical ? canvas.width : canvas.height
        var edges = [0, extent]
        var centers = [extent / 2]
        for other in others {
            let low = axis == .vertical ? other.minX : other.minY
            let high = axis == .vertical ? other.maxX : other.maxY
            // Line up with a neighbour's edges, or sit one gap away from it.
            edges += [low, high, low - gap, high + gap]
            centers.append((low + high) / 2)
        }
        return (edges, centers)
    }

    private static func nearest(
        _ candidates: [(value: Double, lines: [Double])],
        threshold: Double
    ) -> (adjustment: Double, line: Double)? {
        var best: (adjustment: Double, line: Double)?
        for candidate in candidates {
            for line in candidate.lines {
                let adjustment = line - candidate.value
                guard abs(adjustment) <= threshold else { continue }
                if best == nil || abs(adjustment) < abs(best!.adjustment) {
                    best = (adjustment, line)
                }
            }
        }
        return best
    }
}
