import Foundation

/// Platform-neutral geometry, named so as not to collide with the `Rect`, `Size`
/// and `Point` that macOS headers already define. The origin is the top-left
/// corner and y grows downwards, which matches the flipped views the app
/// draws into.
public struct LayoutPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = LayoutPoint(x: 0, y: 0)
}

public struct LayoutSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = LayoutSize(width: 0, height: 0)
}

public struct LayoutRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = LayoutRect(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var size: LayoutSize { LayoutSize(width: width, height: height) }
    public var origin: LayoutPoint { LayoutPoint(x: x, y: y) }
    public var area: Double { max(0, width) * max(0, height) }

    public func contains(_ point: LayoutPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func offsetBy(dx: Double, dy: Double) -> LayoutRect {
        LayoutRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    public func insetBy(dx: Double, dy: Double) -> LayoutRect {
        LayoutRect(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
    }

    public func intersects(_ other: LayoutRect) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }

    /// Area shared with `other`; zero when the two do not overlap.
    public func overlapArea(with other: LayoutRect) -> Double {
        let w = min(maxX, other.maxX) - max(minX, other.minX)
        let h = min(maxY, other.maxY) - max(minY, other.minY)
        return w > 0 && h > 0 ? w * h : 0
    }

    /// Shortest distance from `point` to this rect; zero when the point is inside.
    public func distance(to point: LayoutPoint) -> Double {
        let dx = max(minX - point.x, 0, point.x - maxX)
        let dy = max(minY - point.y, 0, point.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Treats `self` as fractions of a canvas (0...1) and returns points.
    public func scaled(to canvas: LayoutSize) -> LayoutRect {
        LayoutRect(
            x: x * canvas.width,
            y: y * canvas.height,
            width: width * canvas.width,
            height: height * canvas.height
        )
    }

    /// Converts a rect in points to fractions of `canvas`.
    public func normalized(in canvas: LayoutSize) -> LayoutRect {
        guard canvas.width > 0, canvas.height > 0 else { return .zero }
        return LayoutRect(
            x: x / canvas.width,
            y: y / canvas.height,
            width: width / canvas.width,
            height: height / canvas.height
        )
    }

    /// Rounds every edge to whole points so views do not land on half pixels.
    public var integral: LayoutRect {
        let left = x.rounded()
        let top = y.rounded()
        return LayoutRect(x: left, y: top, width: maxX.rounded() - left, height: maxY.rounded() - top)
    }
}
