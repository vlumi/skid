import Foundation

/// Physical footprint shared by every car (one car model for now).
public enum CarGeometry {
    public static let length: Double = 34
    public static let width: Double = 20
    /// Collision radius against walls.
    public static let radius: Double = 12
    /// Tire centers in the car frame (+x = nose): rear pair first, then front.
    public static let tireOffsets: [Vec2] = [
        Vec2(-11, -9), Vec2(-11, 9),
        Vec2(11, -9), Vec2(11, 9),
    ]
}

/// One car's complete dynamic state. Pure value; `Equatable` is exact, which
/// is what the determinism tests assert on.
public struct CarState: Equatable, Sendable, Codable {
    public var position: Vec2
    public var velocity: Vec2
    /// Radians; 0 = +x, counterclockwise in math coords.
    public var heading: Double
    /// Which height layer the car is on.
    public var layer: Int
    /// Ticks of flight remaining; while > 0 the car is ballistic — no
    /// steering, no throttle, no grip, no surface drag.
    public var airborneTicks: Int
    /// The steering actually applied this tick, −1…1. It chases the raw
    /// input at a bounded rate (`CarTuning.steerRate`) instead of matching
    /// it instantly, so a twitchy thumb doesn't snap the nose — the wheel
    /// takes a moment to reach lock. Part of the state so replays stay
    /// bit-exact.
    public var steerActuator: Double

    public init(
        position: Vec2, velocity: Vec2 = .zero, heading: Double = 0, layer: Int = 0,
        airborneTicks: Int = 0, steerActuator: Double = 0
    ) {
        self.position = position
        self.velocity = velocity
        self.heading = heading
        self.layer = layer
        self.airborneTicks = airborneTicks
        self.steerActuator = steerActuator
    }

    public var isAirborne: Bool { airborneTicks > 0 }

    public var forward: Vec2 { Vec2(angle: heading) }

    /// Signed speed along the heading.
    public var forwardSpeed: Double { velocity.dot(forward) }

    /// Magnitude of velocity perpendicular to the heading — how hard the car
    /// is sliding. This is what skid marks key off.
    public var slipSpeed: Double {
        let fwd = forward
        return (velocity - fwd * velocity.dot(fwd)).length
    }

    /// Tire centers in world coordinates (rear pair first).
    public var tirePositions: [Vec2] {
        let fwd = forward
        let side = fwd.perpendicular
        return CarGeometry.tireOffsets.map { position + fwd * $0.x + side * $0.y }
    }
}
