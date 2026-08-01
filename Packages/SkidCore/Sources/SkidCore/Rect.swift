import Foundation

/// An axis-aligned rectangle over `Vec2`. Exists so control-scheme geometry can
/// live in the core rather than reaching for `CGRect`, which would drag
/// CoreGraphics into the sim.
public struct Rect: Equatable, Hashable, Sendable, Codable {
    public var origin: Vec2
    public var size: Vec2

    public init(origin: Vec2, size: Vec2) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: Vec2(x, y), size: Vec2(width, height))
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.x }
    public var maxY: Double { origin.y + size.y }
    public var width: Double { size.x }
    public var height: Double { size.y }
    public var center: Vec2 { Vec2(origin.x + size.x / 2, origin.y + size.y / 2) }

    /// Shrunk by `d` on every side. A rect narrower than `2 * d` collapses to a
    /// negative extent rather than clamping — callers check `width > 0`.
    public func insetBy(_ d: Double) -> Rect {
        Rect(x: origin.x + d, y: origin.y + d, width: size.x - 2 * d, height: size.y - 2 * d)
    }

    /// The nearest point inside the rect.
    public func clamping(_ p: Vec2) -> Vec2 {
        Vec2(min(max(p.x, minX), maxX), min(max(p.y, minY), maxY))
    }
}
