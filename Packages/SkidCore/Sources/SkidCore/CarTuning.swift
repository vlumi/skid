/// The dials the drift feel lives in. Everything here is a candidate for
/// tuning; the defaults are the current best guess at "fun".
public struct CarTuning: Equatable, Sendable, Codable {
    /// Full-throttle acceleration on perfect traction, units/s².
    public var engineAccel: Double
    /// Braking deceleration on perfect traction, units/s².
    public var brakeAccel: Double
    /// Forward top speed, units/s.
    public var maxSpeed: Double
    /// Reverse top speed, units/s.
    public var reverseMaxSpeed: Double
    /// Yaw rate at full steer and full effectiveness, rad/s.
    public var turnRate: Double
    /// Forward speed at which steering reaches full effectiveness — below
    /// it, steering scales down so a parked car can't spin in place.
    public var steerFullSpeed: Double
    /// How fast the steering actuator chases the raw input, in units of
    /// full-deflection per second. It smooths the input (a twitch no longer
    /// snaps the nose) without lowering the ceiling: full lock is still
    /// reached in ~1/steerRate seconds. Agility-neutral, so `scaled(pace:)`
    /// leaves it alone.
    public var steerRate: Double
    /// Velocity kept along the wall normal after a bounce, 0…1.
    public var wallRestitution: Double
    /// Bounciness of car–car contact, 0…1.
    public var carRestitution: Double
    /// Flight ticks per unit of speed off a launching ramp (capped at 1 s).
    public var jumpTicksPerSpeed: Double

    public init(
        engineAccel: Double = 320,
        brakeAccel: Double = 420,
        maxSpeed: Double = 520,
        reverseMaxSpeed: Double = 140,
        turnRate: Double = 3.4,
        steerFullSpeed: Double = 120,
        steerRate: Double = 9,
        wallRestitution: Double = 0.45,
        carRestitution: Double = 0.4,
        jumpTicksPerSpeed: Double = 0.055
    ) {
        self.engineAccel = engineAccel
        self.brakeAccel = brakeAccel
        self.maxSpeed = maxSpeed
        self.reverseMaxSpeed = reverseMaxSpeed
        self.turnRate = turnRate
        self.steerFullSpeed = steerFullSpeed
        self.steerRate = steerRate
        self.wallRestitution = wallRestitution
        self.carRestitution = carRestitution
        self.jumpTicksPerSpeed = jumpTicksPerSpeed
    }

    /// A slowed-down copy for learning: acceleration and speed caps scale
    /// by `pace` (0…1], agility stays — a slower car that turns just as
    /// well is easier, not just slower. Pace 1 is the game.
    public func scaled(pace: Double) -> CarTuning {
        var tuning = self
        tuning.engineAccel *= pace
        tuning.brakeAccel *= pace
        tuning.maxSpeed *= pace
        tuning.reverseMaxSpeed *= pace
        return tuning
    }
}
