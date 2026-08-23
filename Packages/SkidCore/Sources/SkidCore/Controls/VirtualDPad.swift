import Foundation

/// Virtual d-pad, the current default: a d-pad materializes where the thumb
/// lands (clamped inside the player's zone) and STAYS THERE — gas / brake /
/// left / right keep fixed screen positions for the touch's whole life.
/// Displacement toward `up` is throttle (pull back = brake/reverse), sideways
/// is steer, diagonals blend. Per-axis output quantized into `levels` steps
/// with short travel. (Unlike Casual's aim stick, the origin does NOT trail
/// the thumb: with gas usually held and brake rarely, a trailing origin would
/// creep upward and never return.)
public final class VirtualDPadControlSource: TouchDrivenControlSource {
    /// Displacement (points) for full deflection. Short on purpose.
    public var radius: Double = 48
    /// Per-axis dead zone (points) so a resting thumb doesn't creep.
    public var deadzone: Double = 10
    /// Steps per axis direction: 1 = pure digital, nil = fully analog.
    /// Default analog — the on-device feel favorite.
    public var levels: Int?
    /// Response curve: 1 = linear; >1 = softer near center, steeper at
    /// the edges (applied before quantization). Default is a gentle curve.
    public var expo: Double = 1.4
    /// **How much of the zone is the cruise strip**, 0…1 of its height from the
    /// top, or 0 for no strip at all.
    ///
    /// **The strip is the fix for "I cannot find the centre".** A floating pad's
    /// origin is a point on glass with nothing to feel for: after a corner you
    /// hold a little lock you cannot detect and sail down the lane in a slow
    /// sine curve. Reported exactly that way, and neither a longer travel nor a
    /// self-centring wheel cured it — both were trying to synthesise a home
    /// that the LAYOUT can simply provide.
    ///
    /// Inside the strip the throttle is full and the steering is neutral, so a
    /// thumb can slide left and right freely to reposition. Its lower edge is a
    /// boundary a thumb learns by feel, which a point never is. Dropping below
    /// it starts steering, measured from wherever the thumb crossed — so hand
    /// position never matters, and the strip is where the reference is reset.
    public var cruiseStrip: Double = 0.3
    /// How far below the strip steering reaches full authority, in points. The
    /// ramp means a thumb wobbling across the edge does not snap the wheel.
    public var steerFadeDepth: Double = 24
    /// How much of the zone, from the bottom, is braking and reverse. Small on
    /// purpose: reverse only has to get you out of a pinch.
    public var brakeBand: Double = 0.25

    /// **What depth in the zone means**, once past the cruise strip.
    public enum DepthMeaning: String, CaseIterable, Sendable {
        /// Depth selects steering only; the gas stays pinned until the brake
        /// band. Drifting is untouched — throttle held through the slide is
        /// what makes the car slide.
        case steerOnly
        /// **Depth eases the gas, and the steering firms up as it does.** One
        /// continuous relationship rather than two controls: pinned throttle is
        /// fast and straight (steering fades toward nothing and what is left
        /// pulls back to true), and easing off lets the wheel bite so the car
        /// can be placed. Cornering therefore means lifting, as it does in a
        /// real car — and the drift is still reachable, at the throttle where a
        /// real one would break traction.
        case gasAndGrip
    }

    /// Which of the two the pad uses. Both are real designs with different
    /// games behind them, so this is a setting rather than a decision baked in.
    public var depthMeaning: DepthMeaning = .steerOnly

    /// Under `gasAndGrip`, how much steering survives at full throttle, 0…1.
    /// Not zero: a pinned car still needs to be nudged between the walls.
    public var steerAtFullThrottle: Double = 0.35
    /// Under `gasAndGrip`, how hard full throttle pulls the wheel back toward
    /// straight, in full-lock units per second. This is what makes pinned
    /// throttle feel like tracking true rather than like a vague wheel.
    public var throttleRecentring: Double = 2.0
    /// The zone's local "up" in screen coordinates.
    public var up = Vec2(0, -1)
    /// The player's control zone; the pad is clamped to stay fully inside.
    public var bounds: Rect?

    /// Where the pad sits. **It survives the thumb lifting** — the pad stays
    /// visible where the player left it, and the next touch-down moves it —
    /// because a control that only exists while touched appears exactly one
    /// press too late to show a new player where to press. nil only before
    /// the first touch (see `displayOrigin` for the resting default).
    public private(set) var origin: Vec2?
    /// Clamped offset of the thumb from `origin`.
    public private(set) var knob = Vec2.zero

    private var activeTouch: TouchID?
    /// Where the thumb last was, so recentering can recompute the knob without
    /// waiting for a move event that a still thumb never sends.
    private var lastMoved: Vec2?
    /// The tick the wheel last returned for, so a frame that samples the same
    /// tick twice cannot double-step it.
    private var lastTick: Tick = -1
    /// The wheel's current position, -1…1, which lags the thumb on the way back
    /// to centre and matches it on the way out. See `steerReturnRate`.
    private var wheel = 0.0

    /// Whether a thumb is currently down on this pad.
    public var touching: Bool { activeTouch != nil }
    /// Where to DRAW the pad: where the last touch left it, or resting at the
    /// zone's center before any touch. nil only before the zone is laid out.
    public var displayOrigin: Vec2? { origin ?? bounds?.center }

    public init() {}

    public func touchBegan(id: TouchID, at location: Vec2) {
        guard activeTouch == nil else { return }
        activeTouch = id
        origin = clampStick(location, radius: radius, bounds: bounds)
        knob = .zero
        lastMoved = location
        steerAnchor = nil
        lastInStrip = nil
    }

    public func touchMoved(id: TouchID, at location: Vec2) {
        guard id == activeTouch, let origin else { return }
        let offset = location - origin
        let distance = offset.length
        knob = distance > radius ? offset * (radius / distance) : offset
        // **The strip crossing is tracked HERE, not when input is read.**
        // `input(for:at:)` is polled once a tick and a thumb can cross the edge
        // and travel a long way between two polls — anchoring there made
        // straight-ahead depend on polling luck, and a fast swipe into a corner
        // lost the whole turn. Every movement passes through this method.
        if let depth = depth(of: location), cruiseStrip > 0 {
            if depth <= cruiseStrip {
                // In the strip: this is the reference, and re-entering resets it.
                lastInStrip = location.dot(up.perpendicular)
                steerAnchor = nil
            } else if steerAnchor == nil {
                // First movement below: straight-ahead is where the strip was
                // left, or this column if the touch began below it.
                steerAnchor = lastInStrip ?? location.dot(up.perpendicular)
            }
        }
        lastMoved = location
    }

    /// **Where the thumb crossed out of the cruise strip**, along the zone's
    /// sideways axis — straight-ahead for as long as it stays below. Cleared on
    /// lift and whenever the thumb goes back up into the strip, which is what
    /// makes the strip a reset rather than just a dead zone.
    private var steerAnchor: Double?
    /// The sideways column the thumb last held while inside the strip, so a
    /// diagonal exit anchors where the movement STARTED rather than where it
    /// had already reached.
    private var lastInStrip: Double?

    /// How far down the zone the thumb is, 0 at the top edge and 1 at the
    /// bottom. Nil without a zone to measure against.
    private func depth(of point: Vec2) -> Double? {
        guard let bounds, bounds.height > 0 else { return nil }
        // `up` points away from the player, so "down the zone" is along -up.
        let fromTop = (point - Vec2(bounds.center.x, bounds.center.y)).dot(up * -1)
        return min(1, max(0, fromTop / bounds.height + 0.5))
    }

    public func touchEnded(id: TouchID) {
        guard id == activeTouch else { return }
        // The origin stays: the pad rests where the thumb left it.
        activeTouch = nil
        knob = .zero
        steerAnchor = nil
    }

    public func releaseAll() {
        activeTouch = nil
        origin = nil
        knob = .zero
        wheel = 0
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard touching, let finger = lastMoved else { return .coast }
        _ = tick
        guard let bounds, let depth = depth(of: finger), cruiseStrip > 0 else {
            // No zone to divide (tests, or a strip turned off): the old
            // floating pad, unchanged.
            steerAnchor = nil
            return CarInput(
                steer: quantizedAxis(
                    knob.dot(up.perpendicular), deadzone: deadzone, travel: radius,
                    levels: levels, expo: expo),
                throttle: quantizedAxis(
                    knob.dot(up), deadzone: deadzone, travel: radius, levels: levels,
                    expo: expo))
        }

        let across = up.perpendicular
        let sideways = finger.dot(across)

        // **In the strip: full throttle, no steering, free to reposition.**
        // The reference itself is maintained in `touchMoved`.
        guard depth > cruiseStrip else {
            return CarInput(steer: 0, throttle: 1)
        }

        // Below the strip. Straight-ahead is where the thumb was while it was
        // still IN the strip — hand position never matters, only movement from
        // there.
        //
        // The last in-strip column, not the first below it: a thumb crossing
        // the edge diagonally (which is what a swipe into a corner looks like)
        // would otherwise anchor itself mid-swipe and throw away the very
        // movement that was asking for the turn.
        let anchor = steerAnchor ?? lastInStrip ?? sideways

        // **Faded in over the first few points**, so a thumb wobbling across
        // the edge does not snap the wheel.
        let below = (depth - cruiseStrip) * bounds.height
        let authority = steerFadeDepth > 0 ? min(1, below / steerFadeDepth) : 1
        // Full lock at the zone edge, which is far more travel than the old
        // 48-point pad had — and the zone is the widest thing available.
        let travel = max(1, bounds.width / 2)
        var steer = quantizedAxis(
            sideways - anchor, deadzone: deadzone, travel: travel, levels: levels,
            expo: expo)

        // **Braking is the bottom band**, and small: reverse only has to get
        // you out of a pinch, while everything above it is driving.
        let brakeFrom = 1 - brakeBand
        var throttle: Double
        if brakeBand > 0, depth > brakeFrom {
            let into = (depth - brakeFrom) / brakeBand
            throttle = -min(1, into)
        } else {
            throttle = 1
        }

        if depthMeaning == .gasAndGrip, throttle > 0 {
            // **One relationship, not two controls.** Depth eases the gas, and
            // the steering firms up as it does: pinned throttle is fast and
            // straight, easing off lets the wheel bite. Cornering means
            // lifting, as it does in a real car.
            let drivable = max(0.0001, brakeFrom - cruiseStrip)
            let into = min(1, (depth - cruiseStrip) / drivable)
            throttle = 1 - into
            // Full gas keeps only a nudge of steering; lifting restores it all.
            steer *= steerAtFullThrottle + (1 - steerAtFullThrottle) * into
            // And at full gas the wheel pulls back to true, which is what makes
            // a pinned car track straight instead of wandering.
            let pull = throttleRecentring * (1 - into) / Double(Race.tickRate)
            if abs(steer) <= pull {
                steer = 0
            } else {
                steer += steer < 0 ? pull : -pull
            }
        }
        return CarInput(steer: steer * authority, throttle: throttle)
        return CarInput(steer: steer * authority, throttle: throttle)
    }
}
