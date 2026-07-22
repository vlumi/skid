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
    /// Human imperfection: amplitude of a slow, deterministic steering sway
    /// that keeps the driver off the perfect line. 0 = metronome.
    public var wobble: Double
    /// Human imperfection, the bigger one: how far (units) the driver's
    /// AIMED line slowly wanders off the centerline — beyond the ribbon's
    /// half-width, the driver genuinely runs wide onto the grass and has to
    /// recover. 0 = always the right line.
    public var lineWander: Double
    /// Phase shift for the imperfection clocks, so a grid of equal drivers
    /// doesn't wander in lockstep.
    public var phase: Double

    private var stuckTicks = 0
    private var reverseTicks = 0
    /// Ticks lived — phases the wobble; part of state, so replays match.
    private var age = 0

    public init(
        lookahead: Double = 150,
        steerGain: Double = 2.2,
        throttleCap: Double = 1.0,
        cornerCaution: Double = 1.0,
        wobble: Double = 0,
        lineWander: Double = 0,
        phase: Double = 0
    ) {
        self.lookahead = lookahead
        self.steerGain = steerGain
        self.throttleCap = throttleCap
        self.cornerCaution = cornerCaution
        self.wobble = wobble
        self.lineWander = lineWander
        self.phase = phase
    }

    /// Selectable strength. Even `hard` is deliberately not the perfect
    /// default driver — humans deserve a chance.
    public enum Difficulty: CaseIterable, Sendable, Codable {
        case easy
        case medium
        case hard
    }

    /// A driver of the given difficulty; `gridIndex` varies drivers within
    /// one race so the field spreads out.
    public static func make(_ difficulty: Difficulty, gridIndex: Int = 0) -> AIDriver {
        let spread = Double(gridIndex)
        let phase = spread * 2.1
        switch difficulty {
        case .easy:
            return AIDriver(
                lookahead: 115, throttleCap: 0.58 - spread * 0.04,
                cornerCaution: 2.0 + spread * 0.2, wobble: 0.35,
                lineWander: 85, phase: phase)
        case .medium:
            return AIDriver(
                lookahead: 135, throttleCap: 0.74 - spread * 0.04,
                cornerCaution: 1.5 + spread * 0.15, wobble: 0.18,
                lineWander: 35, phase: phase)
        case .hard:
            return AIDriver(
                lookahead: 150, throttleCap: 0.94 - spread * 0.03,
                cornerCaution: 1.05 + spread * 0.12, wobble: 0.06,
                lineWander: 12, phase: phase)
        }
    }

    /// The driver's input for this tick. `mutating` only for the stuck-
    /// recovery memory and the wobble clock; everything else is a pure
    /// function of car + track.
    public mutating func input(car: CarState, track: Track) -> CarInput {
        age += 1
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

        // Aim at a point down the racing line (the centerline, for now) —
        // shifted sideways by the slow line-wander, so weaker drivers
        // confidently follow a wrong line and run wide instead of merely
        // twitching on the right one.
        let lineTarget = track.pointAlongCenterline(
            from: car.position, distance: lookahead, preferLayer: car.layer)
        let wander = lineWander * sin(Double(age) * 0.011 + phase)
        let target = lineTarget + (lineTarget - car.position).normalized.perpendicular * wander
        let toTarget = target - car.position
        let desired = atan2(toTarget.y, toTarget.x)
        let rawError = desired - car.heading
        let error = atan2(sin(rawError), cos(rawError))  // wrap to [-π, π]
        // The sway: a slow sine over the driver's own clock — deterministic,
        // but keeps weaker drivers visibly human, drifting off-line and
        // correcting.
        let sway = wobble * sin(Double(age) * 0.045 + phase)
        let steer = max(-1, min(1, error * steerGain + sway))

        // Lift for corners: compare the near line direction with the line
        // direction further ahead; the more they disagree, the harder the
        // driver breathes. Badly misaligned (spun, recovering) → crawl.
        let ahead = track.pointAlongCenterline(
            from: car.position, distance: lookahead * 2.5, preferLayer: car.layer)
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
