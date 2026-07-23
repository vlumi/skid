import CoreGraphics
import Foundation
import SkidCore

/// Identifies one finger for its whole down–move–up life.
public typealias TouchID = Int

/// A control scheme driven by touches. The routing layer feeds it
/// id-tagged screen points (a player's zone can host several fingers); the
/// sim only ever sees the `CarInput` it produces.
///
/// Every touch scheme carries its own `up` vector: the scheme's axes are
/// defined against it, so a per-player control zone can be rotated to face
/// its player (corner seating on a shared screen) without the scheme
/// knowing. Default is screen-up.
public protocol TouchDrivenControlSource: ControlSource, AnyObject {
    func touchBegan(id: TouchID, at location: Vec2)
    func touchMoved(id: TouchID, at location: Vec2)
    func touchEnded(id: TouchID)
    /// Drop every in-flight touch (scheme switch, race reset).
    func releaseAll()
}

/// The scheme roster, A/B-able in-run.
public enum ControlScheme: CaseIterable, Sendable {
    case dpad
    case aim
    case slide
    case twoZone
    case oneTouch
    case split
}

/// A touch scheme that steers toward a pointed direction needs to know
/// where the car is currently facing (world heading, radians) and how fast
/// it's going (the flip-vs-reverse decision). The routing layer sets this
/// each tick, before `input(for:at:)`; touch-only schemes ignore it.
public protocol HeadingAwareControlSource: TouchDrivenControlSource {
    func setCar(heading: Double, speed: Double)
}

/// Deadzone + travel + optional response curve + step quantization shared
/// by the thumb schemes. `expo` > 1 bends the response: soft near the
/// center (small thumb moves stay gentle), building toward the edges.
func quantizedAxis(
    _ value: Double, deadzone: Double, travel: Double, levels: Int?, expo: Double = 1
) -> Double {
    let magnitude = abs(value)
    guard magnitude > deadzone else { return 0 }
    var scaled = min(1, (magnitude - deadzone) / (travel - deadzone))
    if expo != 1 {
        scaled = pow(scaled, expo)
    }
    if let levels, levels > 0 {
        scaled = (scaled * Double(levels)).rounded(.up) / Double(levels)
    }
    return (value < 0 ? -1 : 1) * scaled
}

/// Virtual d-pad, the current default: a d-pad materializes where the thumb
/// lands (clamped inside the player's zone); displacement toward `up` is
/// throttle (pull back = brake/reverse), sideways is steer, diagonals
/// blend. Per-axis output quantized into `levels` steps with short travel.
public final class VirtualDPadControlSource: TouchDrivenControlSource {
    /// Displacement (points) for full deflection. Short on purpose.
    public var radius: Double = 48
    /// Per-axis dead zone (points) so a resting thumb doesn't creep.
    public var deadzone: Double = 10
    /// Steps per axis direction: 1 = pure digital, nil = fully analog.
    /// Default analog — the on-device feel favourite.
    public var levels: Int?
    /// Response curve: 1 = linear; >1 = softer near center, steeper at
    /// the edges (applied before quantization). Default is a gentle curve.
    public var expo: Double = 1.4
    /// The zone's local "up" in screen coordinates.
    public var up = Vec2(0, -1)
    /// The player's control zone; the pad is clamped to stay fully inside.
    public var bounds: CGRect?

    /// Where the pad materialized; nil while not touching.
    public private(set) var origin: Vec2?
    /// Clamped offset of the thumb from `origin`.
    public private(set) var knob = Vec2.zero

    private var activeTouch: TouchID?

    public init() {}

    public func touchBegan(id: TouchID, at location: Vec2) {
        guard activeTouch == nil else { return }
        activeTouch = id
        origin = clamped(location)
        knob = .zero
    }

    public func touchMoved(id: TouchID, at location: Vec2) {
        guard id == activeTouch, let origin else { return }
        var offset = location - origin
        let distance = offset.length
        if distance > radius { offset *= radius / distance }
        knob = offset
    }

    public func touchEnded(id: TouchID) {
        guard id == activeTouch else { return }
        releaseAll()
    }

    public func releaseAll() {
        activeTouch = nil
        origin = nil
        knob = .zero
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard origin != nil else { return .coast }
        return CarInput(
            steer: quantizedAxis(
                knob.dot(up.perpendicular), deadzone: deadzone, travel: radius,
                levels: levels, expo: expo),
            throttle: quantizedAxis(
                knob.dot(up), deadzone: deadzone, travel: radius, levels: levels, expo: expo)
        )
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

/// Aim-to-drive: a floating stick like the d-pad, but the thumb's ANGLE is
/// the direction you want to go — the sim flips the car's body toward it
/// (speed-scaled) and the drift carries the speed there. Backing up happens
/// only at low speed, where there's no inertia to flip with. No gas/brake
/// to juggle: push where you want to be. Needs the car's heading + speed,
/// so it's a `HeadingAwareControlSource`.
public final class AimControlSource: HeadingAwareControlSource {
    /// Displacement (points) at which the aim is at full commitment (full
    /// throttle when roughly ahead). Short, like the d-pad.
    public var radius: Double = 48
    /// Thumb offsets shorter than this (points) don't aim — a resting or
    /// barely-nudged thumb coasts rather than snapping to a direction.
    public var deadzone: Double = 10
    /// Steer ramp for the REVERSE manoeuvre: full lock once the target is
    /// this many radians off the tail.
    public var fullSteerError = Double.pi / 3
    /// Past this much error (radians) the target counts as "behind".
    public var reverseThreshold = Double.pi * 2 / 3
    /// Below this speed (units/s) a behind-target reverses toward it; at
    /// speed the body flips instead — reversing is a parking-lot move.
    public var reverseBelowSpeed = 90.0
    /// How much the gas eases off as the aim swings away from the nose,
    /// 0…1 of the commitment at a full 180°. Low: flips want throttle held
    /// through the drift.
    public var throttleEase = 0.25
    /// The player's control zone; the stick is clamped to stay inside.
    public var bounds: CGRect?

    /// Where the stick materialized; nil while not touching.
    public private(set) var origin: Vec2?
    /// Clamped offset of the thumb from `origin`.
    public private(set) var knob = Vec2.zero

    private var activeTouch: TouchID?
    private var carHeading = 0.0
    private var carSpeed = 0.0

    public init() {}

    public func setCar(heading: Double, speed: Double) {
        carHeading = heading
        carSpeed = speed
    }

    public func touchBegan(id: TouchID, at location: Vec2) {
        guard activeTouch == nil else { return }
        activeTouch = id
        origin = clamped(location)
        knob = .zero
    }

    public func touchMoved(id: TouchID, at location: Vec2) {
        guard id == activeTouch, let origin else { return }
        var offset = location - origin
        let distance = offset.length
        if distance > radius { offset *= radius / distance }
        knob = offset
    }

    public func touchEnded(id: TouchID) {
        guard id == activeTouch else { return }
        releaseAll()
    }

    public func releaseAll() {
        activeTouch = nil
        origin = nil
        knob = .zero
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard origin != nil, knob.length > deadzone else { return .coast }
        // The thumb offset is a SCREEN-space vector, and the renderer draws
        // the world with no y-flip, so a screen direction IS a world
        // direction — the aimed heading is just the knob's angle. (Unlike
        // the d-pad, `up` doesn't enter: you point at an absolute spot on
        // screen, wherever you're seated.)
        let desired = atan2(knob.y, knob.x)
        let error = atan2(sin(desired - carHeading), cos(desired - carHeading))

        // How committed the push is scales the pace (a light touch eases).
        let commitment = min(1, (knob.length - deadzone) / (radius - deadzone))
        if abs(error) > reverseThreshold, carSpeed < reverseBelowSpeed {
            // Target behind and too slow to flip: back toward it. Reversing
            // mirrors the wheel, so steer toward the target's reflection.
            let back = atan2(sin(desired - carHeading + .pi), cos(desired - carHeading + .pi))
            let steer = max(-1, min(1, back / fullSteerError))
            return CarInput(steer: steer, throttle: -commitment)
        }
        // Hand the aim to the sim — the body-flip lives in the physics.
        // The gas eases a touch as the aim swings away from the nose, but
        // stays largely on: the flip wants throttle held through the drift.
        let throttle = commitment * (1 - throttleEase * min(1, abs(error) / .pi))
        return CarInput(throttle: throttle, aim: desired)
    }

    /// Keep the whole stick inside the zone (mirrors the d-pad).
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

/// Arcade touch-pad ("slide"): thumb down = full gas, sideways offset from
/// touch-start = steer, release = coast. A/B verdict so far: binary
/// always-on gas suits physical buttons better than glass.
public final class TouchPadControlSource: TouchDrivenControlSource {
    /// Thumb travel along the steer axis (points) for full steer.
    public var steerTravel: Double = 70
    /// The zone's local "up" in screen coordinates.
    public var up = Vec2(0, -1)

    private var activeTouch: TouchID?
    private var start: Vec2?
    private var current = Vec2.zero

    public init() {}

    public func touchBegan(id: TouchID, at location: Vec2) {
        guard activeTouch == nil else { return }
        activeTouch = id
        start = location
        current = location
    }

    public func touchMoved(id: TouchID, at location: Vec2) {
        guard id == activeTouch else { return }
        current = location
    }

    public func touchEnded(id: TouchID) {
        guard id == activeTouch else { return }
        releaseAll()
    }

    public func releaseAll() {
        activeTouch = nil
        start = nil
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard let start else { return .coast }
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

    private var activeTouch: TouchID?
    private var location: Vec2?

    public init() {}

    public func touchBegan(id: TouchID, at location: Vec2) {
        guard activeTouch == nil else { return }
        activeTouch = id
        self.location = location
    }

    public func touchMoved(id: TouchID, at location: Vec2) {
        guard id == activeTouch else { return }
        self.location = location
    }

    public func touchEnded(id: TouchID) {
        guard id == activeTouch else { return }
        releaseAll()
    }

    public func releaseAll() {
        activeTouch = nil
        location = nil
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard let location else { return .coast }
        let center = bounds.map { Vec2($0.midX, $0.midY) } ?? location
        let sideways = (location - center).dot(up.perpendicular)
        let steer: Double = sideways == 0 ? 0 : (sideways < 0 ? -1 : 1)
        return CarInput(steer: steer, throttle: 1)
    }
}

/// One-touch: permanent gas; **hold turns, a quick tap flips the turning
/// direction**. One timing gate: a touch shorter than `tapTicks` is a flip.
public final class OneTouchControlSource: TouchDrivenControlSource {
    /// Touches shorter than this (sim ticks, ~0.18 s) count as a tap.
    public var tapTicks: Tick = 11

    private var activeTouch: TouchID?
    private var heldTicks = 0
    private var direction: Double = -1  // start turning left, like the loop

    public init() {}

    public func touchBegan(id: TouchID, at location: Vec2) {
        guard activeTouch == nil else { return }
        activeTouch = id
        heldTicks = 0
    }

    public func touchMoved(id: TouchID, at location: Vec2) {}

    public func touchEnded(id: TouchID) {
        guard id == activeTouch else { return }
        if heldTicks < tapTicks {
            direction = -direction
        }
        releaseAll()
    }

    public func releaseAll() {
        activeTouch = nil
        heldTicks = 0
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard activeTouch != nil else { return CarInput(steer: 0, throttle: 1) }
        heldTicks += 1
        // Only steer once the touch outlives a tap, so a flip doesn't twitch
        // the car the wrong way first.
        return CarInput(steer: heldTicks >= tapTicks ? direction : 0, throttle: 1)
    }
}

/// Split gas/steer, the two-thumb scheme: the zone's steer half (left of
/// its center, in the zone's frame) hosts one thumb steering by sideways
/// drag; the throttle half hosts the other, gas/brake by drag along `up`.
/// Both axes quantized like the d-pad.
public final class SplitControlSource: TouchDrivenControlSource {
    public var travel: Double = 55
    public var deadzone: Double = 8
    public var levels: Int? = 3
    public var up = Vec2(0, -1)
    /// The player's control zone; halves split across its center.
    public var bounds: CGRect?

    private struct Thumb {
        var id: TouchID
        var start: Vec2
        var current: Vec2
    }

    private var steerThumb: Thumb?
    private var throttleThumb: Thumb?

    public init() {}

    public func touchBegan(id: TouchID, at location: Vec2) {
        let center = bounds.map { Vec2($0.midX, $0.midY) } ?? location
        let isSteerHalf = (location - center).dot(up.perpendicular) < 0
        if isSteerHalf {
            guard steerThumb == nil else { return }
            steerThumb = Thumb(id: id, start: location, current: location)
        } else {
            guard throttleThumb == nil else { return }
            throttleThumb = Thumb(id: id, start: location, current: location)
        }
    }

    public func touchMoved(id: TouchID, at location: Vec2) {
        if steerThumb?.id == id { steerThumb?.current = location }
        if throttleThumb?.id == id { throttleThumb?.current = location }
    }

    public func touchEnded(id: TouchID) {
        if steerThumb?.id == id { steerThumb = nil }
        if throttleThumb?.id == id { throttleThumb = nil }
    }

    public func releaseAll() {
        steerThumb = nil
        throttleThumb = nil
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        var steer = 0.0
        var throttle = 0.0
        if let thumb = steerThumb {
            steer = quantizedAxis(
                (thumb.current - thumb.start).dot(up.perpendicular),
                deadzone: deadzone, travel: travel, levels: levels)
        }
        if let thumb = throttleThumb {
            throttle = quantizedAxis(
                (thumb.current - thumb.start).dot(up),
                deadzone: deadzone, travel: travel, levels: levels)
        }
        return CarInput(steer: steer, throttle: throttle)
    }
}
