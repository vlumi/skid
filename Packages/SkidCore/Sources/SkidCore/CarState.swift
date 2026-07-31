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
    /// How high the car is: 0 = ground, 1 = bridge deck, in between while on a
    /// ramp.
    ///
    /// Continuous, and **followed from the road** rather than switched at a line.
    /// The old discrete `layer: Int` had to be flipped when the car crossed a
    /// ramp's transition line, and every bug around bridges came from that: the
    /// pop as it flipped, the road vanishing mid-transition, and a car under the
    /// bridge emerging on top of the ramp. Deriving it from the road each tick
    /// makes those states unreachable rather than guarded.
    public var height: Double
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
        position: Vec2, velocity: Vec2 = .zero, heading: Double = 0, height: Double = 0,
        airborneTicks: Int = 0, steerActuator: Double = 0
    ) {
        self.position = position
        self.velocity = velocity
        self.heading = heading
        self.height = height
        self.airborneTicks = airborneTicks
        self.steerActuator = steerActuator
    }

    public var isAirborne: Bool { airborneTicks > 0 }

    public var forward: Vec2 { Vec2(angle: heading) }

    /// Signed speed along the heading.
    public var forwardSpeed: Double { velocity.dot(forward) }

    /// **What the last tick's wall contact did**, for the debug overlay only.
    ///
    /// Wall feel could not be diagnosed from tests: every probe either missed
    /// contact or measured its own harness, while the device reported the car
    /// gluing to walls. So the sim records what it actually did and the overlay
    /// shows it. Not part of the sim's behaviour — nothing reads these but the
    /// overlay — but it IS part of the state, so lockstep replays carry it.
    public struct WallContact: Equatable, Sendable, Codable {
        /// How many wall segments were responded to in the tick.
        public var hits = 0
        /// Into-wall closing speed of the hardest one.
        public var press = 0.0
        /// 0 = a pure glance, 1 = head-on.
        public var squareness = 0.0
        /// Speed the car had along the wall, before the response.
        public var slide = 0.0
        /// Speed the whole car lost across the tick (wall AND everything else).
        public var speedLost = 0.0

        // **Held values, so a screenshot is readable.** A single tick is 1/60 s and
        // nobody can time a screen grab to one — so the overlay shows sustained
        // figures too: how long contact has run, the worst tick in it, and the total
        // it has cost. They reset once the car has been clear for a moment.

        /// Consecutive ticks with contact (0 once clear).
        public var ticks = 0
        /// Ticks since the last contact, so a brief bounce doesn't reset the run.
        public var idleTicks = 0
        /// Worst single-tick speed loss during this run of contact.
        public var worstLoss = 0.0
        /// Total speed lost across this run of contact.
        public var totalLoss = 0.0
        /// Speed when this run of contact began, to compare against now.
        public var speedAtStart = 0.0
    }

    /// Last tick's wall contact — debug only, see `WallContact`.
    public var wallContact = WallContact()

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

    /// The drawn body's four corners in world coordinates. The tires are inset
    /// from the body (the nose and tail overhang the axles), so anything that
    /// cares about the car's visual extent — like which render pass may paint
    /// over it — has to ask the corners, not the tires.
    public var bodyCorners: [Vec2] {
        let fwd = forward * (CarGeometry.length / 2)
        let side = forward.perpendicular * (CarGeometry.width / 2)
        return [
            position + fwd + side, position + fwd - side,
            position - fwd + side, position - fwd - side,
        ]
    }
}
