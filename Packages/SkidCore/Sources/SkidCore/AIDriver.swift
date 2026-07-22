import Foundation

/// An AI opponent is just another input source: a pure, deterministic
/// function of the car's state and the track, producing the same
/// car-relative `CarInput` a thumb would. No rubber-banding — difficulty
/// comes from the same dials the player's car uses (lookahead, throttle
/// cap, corner caution), so AI cars are mechanically identical.
public struct AIDriver: Equatable, Sendable, Codable {
    /// How far ahead on the centerline the driver aims, units.
    public var lookahead: Double
    /// Steering response per radian of heading error.
    public var steerGain: Double
    /// Skill: top throttle the driver ever uses, 0…1.
    public var throttleCap: Double
    /// Skill: how hard upcoming curvature scares the driver off the gas.
    public var cornerCaution: Double

    private var stuckTicks = 0
    private var reverseTicks = 0

    public init(
        lookahead: Double = 150,
        steerGain: Double = 2.2,
        throttleCap: Double = 1.0,
        cornerCaution: Double = 1.0
    ) {
        self.lookahead = lookahead
        self.steerGain = steerGain
        self.throttleCap = throttleCap
        self.cornerCaution = cornerCaution
    }

    /// A skill ladder for grid-filling: index 0 is the quickest.
    public static func skill(_ index: Int) -> AIDriver {
        AIDriver(
            lookahead: 150 - Double(index) * 10,
            throttleCap: 1.0 - Double(index) * 0.06,
            cornerCaution: 1.0 + Double(index) * 0.25
        )
    }

    /// The driver's input for this tick. `mutating` only for the stuck-
    /// recovery memory; everything else is a pure function of car + track.
    public mutating func input(car: CarState, track: Track) -> CarInput {
        // Pinned against a wall at ~zero speed: back out for a moment.
        if reverseTicks > 0 {
            reverseTicks -= 1
            return CarInput(steer: 0, throttle: -1)
        }
        if car.velocity.length < 25 {
            stuckTicks += 1
        } else {
            stuckTicks = 0
        }
        if stuckTicks > 45 {  // ~0.75 s stationary
            stuckTicks = 0
            reverseTicks = 40
            return CarInput(steer: 0, throttle: -1)
        }

        // Aim at a point down the racing line (the centerline, for now).
        let target = track.pointAlongCenterline(from: car.position, distance: lookahead)
        let toTarget = target - car.position
        let desired = atan2(toTarget.y, toTarget.x)
        let rawError = desired - car.heading
        let error = atan2(sin(rawError), cos(rawError))  // wrap to [-π, π]
        let steer = max(-1, min(1, error * steerGain))

        // Lift for corners: compare the near line direction with the line
        // direction further ahead; the more they disagree, the harder the
        // driver breathes. Badly misaligned (spun, recovering) → crawl.
        let ahead = track.pointAlongCenterline(from: car.position, distance: lookahead * 2.5)
        let nearDirection = toTarget.normalized
        let farDirection = (ahead - target).normalized
        let turniness = 1 - nearDirection.dot(farDirection)  // 0 straight … 2 U-turn
        let throttle: Double
        if abs(error) > 1.1 {
            throttle = 0.15
        } else {
            throttle = max(0.3, throttleCap - turniness * cornerCaution * 1.1)
        }
        return CarInput(steer: steer, throttle: throttle)
    }
}
