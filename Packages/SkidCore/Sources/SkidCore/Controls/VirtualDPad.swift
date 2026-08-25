import Foundation

/// **The Pro pad: the player's whole zone is one control.**
///
/// Steering is mouse-style — sideways MOVEMENT winds the wheel, stillness
/// lets it recentre at a speed-weighted rate — so there is no centre to lose
/// and no lock to hold: a corner is a gesture, straight is the absence of
/// one. Depth in the zone is one continuous gas axis: full throttle at the
/// top, coasting at `coastDepth`, full reverse at the bottom — pulling back
/// brakes while the car still rolls and reverses once it stops, which is the
/// sim's own reading of negative throttle. Deeper also firms the steering
/// (gas + grip): pinned throttle keeps only `steerAtFullThrottle` of the
/// wheel, easing off lets it bite.
///
/// This is the survivor of a long device-play elimination: a floating pad
/// (no findable centre), a from-entry anchor (too sticky), a steering-free
/// cruise strip and a brake band (both got in the way once the recentring
/// found straight on its own). The one model left needs no mode switches.
/// The old floating pad remains ONLY as the bounds-nil fallback below.
public final class VirtualDPadControlSource: HeadingAwareControlSource {
    // MARK: - The floating fallback's knobs (bounds == nil only)

    /// Displacement (points) for full deflection of the FALLBACK pad.
    public var radius: Double = 48
    /// Per-axis dead zone (points) of the FALLBACK pad.
    public var deadzone: Double = 10
    /// Fallback quantization: steps per axis, nil = analog.
    public var levels: Int?
    /// Fallback response curve.
    public var expo: Double = 1.4

    // MARK: - The zoned pad's dials

    /// Sideways points of movement for full lock.
    public var steerTravel: Double = 35
    /// How fast a STILL thumb's wheel returns to straight, in full-lock units
    /// per second — the rate at full weight, before the speed scaling below.
    public var steerRecentring: Double = 1.2
    /// How much car speed scales the recentring, 0…1: 0 is a constant rate,
    /// 1 (the driven-in default) is fully proportional — self-aligning
    /// torque, so straights at speed hold themselves while a car easing
    /// through a pinch keeps its lock entirely.
    public var recentringSpeedWeight: Double = 1.0
    /// The speed (units/s) where speed-weighted recentring saturates; wired
    /// to the car's top speed by the tuning layer.
    public var fullSpeed: Double = 520
    /// How much steering survives at full throttle, 0…1 — the grip half of
    /// gas + grip. Not zero: a pinned car still needs nudging between walls.
    public var steerAtFullThrottle: Double = 0.5
    /// Where on the zone the gas runs out, 0…1 from the top: above it the
    /// throttle ramps 1→0, below it 0→−1. One continuous axis — "pushing
    /// backwards is reverse" — with no band chrome to find.
    public var coastDepth: Double = 0.6

    /// The zone's local "up" in screen coordinates.
    public var up = Vec2(0, -1)
    /// The player's control zone. With no zone the pad degrades to the old
    /// floating stick (tests, bare use); a zone always gets the zoned pad.
    public var bounds: Rect?

    /// Where the fallback pad sits; survives the thumb lifting.
    public private(set) var origin: Vec2?
    /// Clamped offset of the thumb from `origin` (fallback display).
    public private(set) var knob = Vec2.zero

    private var activeTouch: TouchID?
    /// Where the thumb last was — the zoned pad's only position input.
    private var lastMoved: Vec2?
    /// The tick the wheel last recentred for, so a frame that samples the
    /// same tick twice cannot double-step it.
    private var lastTick: Tick = -1
    /// The wheel, -1…1: wound by sideways movement in `touchMoved`, unwound
    /// toward zero by `recentreWheel`, dropped on lift.
    private var wheel = 0.0
    /// The car's current speed (units/s), for the speed-weighted recentring.
    private var carSpeed = 0.0

    /// Heading and forward speed are the aim scheme's questions; this pad
    /// only wants how fast the car rolls.
    public func setCar(heading: Double, forwardSpeed: Double, speed: Double) {
        carSpeed = speed
    }

    /// Whether a thumb is currently down on this pad.
    public var touching: Bool { activeTouch != nil }
    /// The thumb's true position while touching — `knob` is clamped to the
    /// fallback radius and lies once the thumb is further out than that.
    public var touchPoint: Vec2? { touching ? lastMoved : nil }
    /// Where to DRAW the fallback pad.
    public var displayOrigin: Vec2? { origin ?? bounds?.center }

    /// **A point on the steering-neutral line, for drawing** — the model made
    /// visible: the line slides left-right with the wheel, steering IS the
    /// thumb's sideways distance from it, and a still thumb watches the line
    /// slide back underneath as the wheel recentres. Only the sideways
    /// component carries meaning (the line is full-height); the returned
    /// point rides at the thumb so a renderer can span from it along `up`.
    /// Derived from the wheel, never stored, so the two cannot disagree.
    public var stickBase: Vec2? {
        guard bounds != nil, touching, let thumb = lastMoved else { return nil }
        return thumb - up.perpendicular * (wheel * max(1, steerTravel))
    }

    public init() {}

    public func touchBegan(id: TouchID, at location: Vec2) {
        guard activeTouch == nil else { return }
        activeTouch = id
        origin = clampStick(location, radius: radius, bounds: bounds)
        knob = .zero
        lastMoved = location
        // A fresh touch starts straight: carrying a dead touch's lock into a
        // new one is the invisible-steer bug in a new costume.
        wheel = 0
    }

    public func touchMoved(id: TouchID, at location: Vec2) {
        guard id == activeTouch, let origin else { return }
        let offset = location - origin
        let distance = offset.length
        knob = distance > radius ? offset * (radius / distance) : offset
        // The wheel winds from MOVEMENT, here where every event is seen —
        // polling only in `input` would drop the travel between two ticks.
        if bounds != nil, let last = lastMoved {
            let delta = (location - last).dot(up.perpendicular)
            wheel = min(1, max(-1, wheel + delta / max(1, steerTravel)))
        }
        lastMoved = location
    }

    public func touchEnded(id: TouchID) {
        guard id == activeTouch else { return }
        activeTouch = nil
        knob = .zero
        // The wheel is NOT dropped here: with no touch, `input` coasts, and
        // `touchBegan` starts every new touch straight — one reset, testable.
    }

    public func releaseAll() {
        activeTouch = nil
        origin = nil
        knob = .zero
        wheel = 0
        // A race restart rewinds the tick counter; a stale lastTick from the
        // old race would silence the recentring until the new race passed it.
        lastTick = -1
    }

    /// How far down the zone the thumb is, 0 at the top edge and 1 at the
    /// bottom. Nil without a zone to measure against.
    private func depth(of point: Vec2) -> Double? {
        guard let bounds, bounds.height > 0 else { return nil }
        let fromTop = (point - Vec2(bounds.center.x, bounds.center.y)).dot(up * -1)
        return min(1, max(0, fromTop / bounds.height + 0.5))
    }

    /// Winds the wheel back toward straight for the ticks since the last
    /// read. Tick-keyed, not call-keyed: the render layer polls the same tick
    /// the sim does, and the pull scales with the tick delta — so a same-tick
    /// re-read pulls zero, and a replay recentres identically.
    private func recentreWheel(at tick: Tick) {
        defer { lastTick = tick }
        guard lastTick >= 0, tick > lastTick else { return }
        let speed = min(1, max(0, carSpeed / max(1, fullSpeed)))
        let rate = steerRecentring * ((1 - recentringSpeedWeight) + recentringSpeedWeight * speed)
        let pull = rate * Double(tick - lastTick) / Double(Race.tickRate)
        if abs(wheel) <= pull {
            wheel = 0
        } else {
            wheel += wheel < 0 ? pull : -pull
        }
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard touching, let finger = lastMoved else { return .coast }
        recentreWheel(at: tick)
        guard depth(of: finger) != nil, let depth = depth(of: finger) else {
            // No zone laid out (tests, or a pad used bare): the old floating
            // pad, unchanged.
            return CarInput(
                steer: quantizedAxis(
                    knob.dot(up.perpendicular), deadzone: deadzone, travel: radius,
                    levels: levels, expo: expo),
                throttle: quantizedAxis(
                    knob.dot(up), deadzone: deadzone, travel: radius, levels: levels,
                    expo: expo))
        }

        var steer = wheel
        let coast = min(0.95, max(0.05, coastDepth))
        let throttle: Double
        if depth <= coast {
            // **Gas + grip, one relationship**: depth eases the gas and the
            // steering firms as it does — pinned throttle is fast and
            // straight, easing off lets the wheel bite.
            let into = depth / coast
            throttle = 1 - into
            steer *= steerAtFullThrottle + (1 - steerAtFullThrottle) * into
        } else {
            // Below coast the same pull keeps going: brake while rolling,
            // reverse once stopped — the sim's own meaning of negative
            // throttle. Steering stays at full bite.
            throttle = -min(1, (depth - coast) / (1 - coast))
        }
        return CarInput(steer: steer, throttle: throttle)
    }
}
