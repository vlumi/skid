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
    /// Base yaw rate toward an `aim` command, rad/s — how eagerly the body
    /// chases where you point. Deliberately far above `turnRate`: the aim
    /// scheme's whole feel is the body answering the thumb.
    public var aimTurnRate: Double
    /// EXTRA aim yaw rate at full speed, rad/s, scaled by |v|/maxSpeed —
    /// the handbrake inertia: the faster you go, the harder you can wrench
    /// the body around. Slow cars flip gently.
    public var aimFlipBoost: Double
    /// The same body-flip, but for the STEER path: holding a direction at
    /// speed rotates the body toward it beyond the wheel's own turn, so the
    /// d-pad (and keyboard, which reuses it) can drift without countersteer.
    /// Scaled by |v|/maxSpeed and the analog steer amount, so a light thumb
    /// still flips gently. rad/s at full speed + full steer.
    public var steerFlipBoost: Double
    /// How much of the speed a drift bleeds off gets redirected along the
    /// nose instead of lost, 0…1. 1 = drifting costs nothing (arcade — flip,
    /// slide, and carry the speed out); 0 = a slide scrubs speed.
    public var driftRetention: Double
    /// Global multiplier on every surface's grip — the "inertia" knob. 1 =
    /// stock; lower = the sideways slide lingers, so the car's MOTION lags
    /// the nose longer (heavier, driftier); higher = motion snaps to the
    /// heading faster. Scales all surfaces together, keeping their relative
    /// feel.
    public var gripScale: Double
    // MARK: - Wall contact
    //
    // **Five knobs, because this is pure feel and was retuned three times from
    // device play.** Which one to turn:
    //
    // - bounces too hard head-on → `wallRestitution` down
    // - brushing a wall feels dead / like flypaper → `wallGlanceBounce` up
    // - wall-riding is too fast a line → `wallFriction` up
    // - dragging a wall grinds to a halt → `wallDragFloor` up (or friction down)
    // - the car doesn't pivot along the wall / fights steering → `wallYaw`
    //
    // The angle band itself (what counts as a glance vs head-on) lives in
    // `Race.glancingAngle` / `Race.headOnAngle`.

    /// Velocity kept along the wall normal after a bounce, 0…1 — at HEAD-ON. It
    /// falls away as the approach flattens, so a graze scrubs instead of kicking
    /// out (see `Race.collideWithWalls`).
    public var wallRestitution: Double
    /// The bounce a pure GLANCE still gets, as a share of `wallRestitution`. Not
    /// zero: no bounce at all made brushing a wall feel like flypaper, so a graze
    /// keeps a subdued kick.
    public var wallGlanceBounce: Double
    /// How much speed ALONG a wall a scrape takes, as a per-second rate per unit of
    /// into-wall speed. This is what makes riding a barrier slower than avoiding it
    /// — with no tangential loss at all, hugging walls was free.
    ///
    /// Small on purpose: `press` is in units/s, so at a racing-speed graze it is in
    /// the hundreds, and this multiplies it. Tuned DOWN twice from device feel —
    /// 0.55 stopped the car dead on contact, then 0.012 still left only 2% of speed
    /// after a second of dragging at 20°, which read as flypaper.
    public var wallFriction: Double
    /// The share of speed a sustained drag settles at, rather than bleeding to a
    /// stop. Dragging a wall should be a viable if slow line — around half speed is
    /// fine for balance — so friction eases off as the car approaches this.
    public var wallDragFloor: Double
    /// How hard a graze pulls the nose parallel to the wall, in rad/s per unit of
    /// into-wall speed. A car with mass pivots along the barrier rather than
    /// skipping off it.
    public var wallYaw: Double
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
        aimTurnRate: Double = 10,
        aimFlipBoost: Double = 8,
        steerFlipBoost: Double = 5,
        driftRetention: Double = 1.0,
        gripScale: Double = 1.0,
        wallRestitution: Double = 0.45,
        wallGlanceBounce: Double = 0.3,
        wallFriction: Double = 0.010,
        wallDragFloor: Double = 0.5,
        wallYaw: Double = 0.012,
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
        self.aimTurnRate = aimTurnRate
        self.aimFlipBoost = aimFlipBoost
        self.steerFlipBoost = steerFlipBoost
        self.driftRetention = driftRetention
        self.gripScale = gripScale
        self.wallRestitution = wallRestitution
        self.wallGlanceBounce = wallGlanceBounce
        self.wallFriction = wallFriction
        self.wallDragFloor = wallDragFloor
        self.wallYaw = wallYaw
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
