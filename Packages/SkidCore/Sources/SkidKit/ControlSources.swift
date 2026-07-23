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

/// The two control schemes. **Casual** is aim-to-drive (point where you
/// want to go, the game handles the drift); **Pro** is the direct
/// steer/throttle d-pad (with flip-assist — and the scheme keyboard reuses).
public enum ControlScheme: CaseIterable, Sendable {
    case casual
    case pro
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

/// A floating stick's new (origin, knob) after the finger moves. Within
/// `radius` the origin holds and the knob follows. Drag PAST the rim and the
/// origin trails the finger (staying `radius` behind), so the knob pins at
/// full deflection AND pushing back the other way instantly un-maxes it —
/// you can swing extreme-to-extreme without lifting, in a zone too narrow to
/// reach full lock otherwise. The trailing origin re-clamps to `bounds` so
/// the stick never wanders off the player's zone.
func floatingStick(
    origin: Vec2, finger: Vec2, radius: Double, bounds: CGRect?
) -> (origin: Vec2, knob: Vec2) {
    let offset = finger - origin
    let distance = offset.length
    guard distance > radius, distance > 0 else { return (origin, offset) }
    let direction = offset * (1 / distance)
    let draggedOrigin = clampStick(finger - direction * radius, radius: radius, bounds: bounds)
    return (draggedOrigin, finger - draggedOrigin)
}

/// Keep a floating stick's origin far enough inside `bounds` that its whole
/// travel circle stays in the zone (shared by touchBegan + drag re-center).
func clampStick(_ p: Vec2, radius: Double, bounds: CGRect?) -> Vec2 {
    guard let bounds else { return p }
    let margin = radius + 18
    let rect = bounds.insetBy(dx: margin, dy: margin)
    guard rect.width > 0, rect.height > 0 else {
        return Vec2(bounds.midX, bounds.midY)
    }
    return Vec2(min(max(p.x, rect.minX), rect.maxX), min(max(p.y, rect.minY), rect.maxY))
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
        origin = clampStick(location, radius: radius, bounds: bounds)
        knob = .zero
    }

    public func touchMoved(id: TouchID, at location: Vec2) {
        guard id == activeTouch, let origin else { return }
        (self.origin, knob) = floatingStick(
            origin: origin, finger: location, radius: radius, bounds: bounds)
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
        origin = clampStick(location, radius: radius, bounds: bounds)
        knob = .zero
    }

    public func touchMoved(id: TouchID, at location: Vec2) {
        guard id == activeTouch, let origin else { return }
        (self.origin, knob) = floatingStick(
            origin: origin, finger: location, radius: radius, bounds: bounds)
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
}
