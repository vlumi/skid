import Foundation

/// 2D vector over `Double`. The sim's only geometry currency — everything
/// deterministic flows through these few operations.
public struct Vec2: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    /// Unit vector at `angle` radians (0 = +x, counterclockwise in math
    /// coords; the renderer decides what that looks like on screen).
    public init(angle: Double) {
        self.init(cos(angle), sin(angle))
    }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    public static func -= (a: inout Vec2, b: Vec2) { a = a - b }
    public static func *= (a: inout Vec2, s: Double) { a = a * s }

    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }
    /// z-component of the 3D cross product — sign gives which side `other`
    /// lies on.
    public func cross(_ other: Vec2) -> Double { x * other.y - y * other.x }

    public var length: Double { (x * x + y * y).squareRoot() }
    public var lengthSquared: Double { x * x + y * y }

    /// Normalized copy; `.zero` stays `.zero` rather than dividing by zero.
    public var normalized: Vec2 {
        let len = length
        return len > 0 ? Vec2(x / len, y / len) : .zero
    }

    /// Perpendicular (rotated +90° in math coords).
    public var perpendicular: Vec2 { Vec2(-y, x) }

    public func distance(to other: Vec2) -> Double { (self - other).length }

    /// Closest point to `self` on segment `a`–`b`.
    public func closestPoint(onSegment a: Vec2, _ b: Vec2) -> Vec2 {
        let ab = b - a
        let denominator = ab.lengthSquared
        guard denominator > 0 else { return a }
        let t = max(0, min(1, (self - a).dot(ab) / denominator))
        return a + ab * t
    }

    /// Distance from `self` to segment `a`–`b`.
    public func distance(toSegment a: Vec2, _ b: Vec2) -> Double {
        distance(to: closestPoint(onSegment: a, b))
    }
}
