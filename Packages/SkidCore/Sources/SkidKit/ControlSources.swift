import CoreGraphics
import Foundation
import SkidCore

/// A control scheme driven by one touch. The gesture layer feeds it screen
/// points; the sim only ever sees the `CarInput` it produces.
///
/// Every touch scheme carries its own `up` vector: the scheme's axes are
/// defined against it, so a per-player control zone can be rotated to face
/// its player (corner seating on a shared screen) without the scheme
/// knowing. Default is screen-up.
public protocol TouchDrivenControlSource: ControlSource, AnyObject {
    func touchChanged(at location: Vec2)
    func touchEnded()
}

/// Virtual d-pad, the current default: a d-pad materializes where the thumb
/// lands; displacement toward `up` is throttle (pull back = brake/reverse),
/// sideways is steer, diagonals blend. Per-axis output is QUANTIZED into
/// `levels` steps ("2-bit digital" by default: half or full deflection) with
/// deliberately short travel — findings from the first on-device trial:
/// steering must work while coasting, but full analog has too much leeway
/// for a thumb on glass.
public final class VirtualDPadControlSource: TouchDrivenControlSource {
    /// Displacement (points) for full deflection. Short on purpose.
    public var radius: Double = 48
    /// Per-axis dead zone (points) so a resting thumb doesn't creep.
    public var deadzone: Double = 10
    /// Steps per axis direction: 1 = pure digital, nil = fully analog.
    /// Default 3 (⅓ / ⅔ / full) — second device trial wanted a bit more
    /// modulation than half/full, still no analog mush.
    public var levels: Int? = 3
    /// The zone's local "up" in screen coordinates.
    public var up = Vec2(0, -1)
    /// The player's control zone (screen points). The pad materializes where
    /// the thumb lands but is clamped to stay fully inside this — the model
    /// that scales to per-player zones on a shared screen. nil = anywhere.
    public var bounds: CGRect?

    /// Where the pad materialized (screen points); nil while not touching.
    public private(set) var origin: Vec2?
    /// Clamped offset of the thumb from `origin`.
    public private(set) var knob = Vec2.zero

    public init() {}

    public func touchChanged(at location: Vec2) {
        if origin == nil { origin = clamped(location) }
        guard let origin else { return }
        var offset = location - origin
        let distance = offset.length
        if distance > radius { offset *= radius / distance }
        knob = offset
    }

    public func touchEnded() {
        origin = nil
        knob = .zero
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard origin != nil else { return .coast }
        return CarInput(
            steer: axis(knob.dot(up.perpendicular)),
            throttle: axis(knob.dot(up))
        )
    }

    private func axis(_ value: Double) -> Double {
        let magnitude = abs(value)
        guard magnitude > deadzone else { return 0 }
        var scaled = min(1, (magnitude - deadzone) / (radius - deadzone))
        if let levels, levels > 0 {
            scaled = (scaled * Double(levels)).rounded(.up) / Double(levels)
        }
        return (value < 0 ? -1 : 1) * scaled
    }

    /// Keep the whole pad (arrows included) inside the zone.
    private func clamped(_ p: Vec2) -> Vec2 {
        guard let bounds else { return p }
        let margin = radius + 18
        let rect = bounds.insetBy(dx: margin, dy: margin)
        guard rect.width > 0, rect.height > 0 else {
            return Vec2(bounds.midX, bounds.midY)
        }
        return Vec2(min(max(p.x, rect.minX), rect.maxX), min(max(p.y, rect.minY), rect.maxY))
    }
}

/// Arcade touch-pad ("slide"), the original scheme, kept as an A/B
/// candidate: thumb down = full gas, horizontal offset from touch-start =
/// steer, release = coast. On-device verdict so far: binary always-on gas
/// suits physical buttons better than glass.
public final class TouchPadControlSource: TouchDrivenControlSource {
    /// Thumb travel along the steer axis (points) for full steer.
    public var steerTravel: Double = 70
    /// The zone's local "up" in screen coordinates.
    public var up = Vec2(0, -1)

    private var start: Vec2?
    private var current = Vec2.zero
    private var touching = false

    public init() {}

    public func touchChanged(at location: Vec2) {
        if start == nil { start = location }
        current = location
        touching = true
    }

    public func touchEnded() {
        start = nil
        touching = false
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard touching, let start else { return .coast }
        let sideways = (current - start).dot(up.perpendicular)
        return CarInput(steer: sideways / steerTravel, throttle: 1)
    }
}

/// Two-zone tap-steer: hold anywhere = gas; which half of the zone the
/// thumb is in (relative to the zone's `up`) picks the steer direction.
/// Digital by design.
public final class TwoZoneControlSource: TouchDrivenControlSource {
    /// The player's control zone; halves are split across its center.
    public var bounds: CGRect?
    /// The zone's local "up" in screen coordinates.
    public var up = Vec2(0, -1)

    private var location: Vec2?

    public init() {}

    public func touchChanged(at location: Vec2) { self.location = location }
    public func touchEnded() { location = nil }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard let location else { return .coast }
        let center = bounds.map { Vec2($0.midX, $0.midY) } ?? location
        let sideways = (location - center).dot(up.perpendicular)
        let steer: Double = sideways == 0 ? 0 : (sideways < 0 ? -1 : 1)
        return CarInput(steer: steer, throttle: 1)
    }
}

/// One-touch: permanent gas; **hold turns, a quick tap flips the turning
/// direction** — the variant that fixes turn-one-way-only (a right turn no
/// longer needs a full circle). One timing gate: a touch shorter than
/// `tapTicks` is a flip, longer is a turn.
public final class OneTouchControlSource: TouchDrivenControlSource {
    /// Touches shorter than this (sim ticks, ~0.18 s) count as a tap.
    public var tapTicks: Tick = 11

    private var touching = false
    private var heldTicks = 0
    private var direction: Double = -1  // start turning left, like the loop

    public init() {}

    public func touchChanged(at location: Vec2) { touching = true }

    public func touchEnded() {
        if touching, heldTicks < tapTicks {
            direction = -direction
        }
        touching = false
        heldTicks = 0
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard touching else { return CarInput(steer: 0, throttle: 1) }
        heldTicks += 1
        // Only steer once the touch outlives a tap, so a flip doesn't twitch
        // the car the wrong way first.
        return CarInput(steer: heldTicks >= tapTicks ? direction : 0, throttle: 1)
    }
}
