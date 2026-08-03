import Foundation

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
    /// `forwardSpeed` is SIGNED — negative while reversing — because "am I
    /// going backwards already" is a different question from "how fast am I
    /// moving", and the flip-vs-reverse decision needs the first.
    func setCar(heading: Double, forwardSpeed: Double, speed: Double)
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
///
/// **When the clamp bites, the stick AIMS instead of trailing.** The origin
/// can only move inside the zone, but the finger can be outside it (the safe
/// area under a notch is untouchable, yet the surrounding inset is not), and
/// then a trailing origin distorts the direction: it slides sideways with the
/// finger while the perpendicular offset stays pinned, so the knob barely
/// turns. Measured on a notched top zone, moving the finger 120 points
/// sideways swung the stick only 20° — the reported "pulling down is easy but
/// turning is nearly impossible". Pinning the knob to the finger's BEARING
/// from the clamped origin keeps full deflection and full steering range: the
/// clamp then bounds where the stick is DRAWN, not what the input MEANS.
func floatingStick(
    origin: Vec2, finger: Vec2, radius: Double, bounds: Rect?
) -> (origin: Vec2, knob: Vec2) {
    let offset = finger - origin
    let distance = offset.length
    guard distance > radius, distance > 0 else { return (origin, offset) }
    let direction = offset * (1 / distance)
    let trailing = finger - direction * radius
    let clamped = clampStick(trailing, radius: radius, bounds: bounds)
    // Un-clamped: the origin really is `radius` behind the finger, so the knob
    // is the finger itself — full deflection along the true bearing.
    guard (clamped - trailing).length > 0.001 else { return (clamped, finger - clamped) }
    // Clamped: the origin STAYS PUT and the knob takes the finger's bearing at
    // full deflection. Letting the origin slide along the clamp edge is what
    // killed steering — it chased the finger sideways while the perpendicular
    // offset stayed pinned, so the bearing barely moved.
    let aim = finger - origin
    guard aim.length > 0.001 else { return (origin, direction * radius) }
    return (origin, aim * (radius / aim.length))
}

/// Keep a floating stick's origin far enough inside `bounds` that its whole
/// travel circle stays in the zone (shared by touchBegan + drag re-center).
func clampStick(_ p: Vec2, radius: Double, bounds: Rect?) -> Vec2 {
    guard let bounds else { return p }
    let margin = radius + 18
    let rect = bounds.insetBy(margin)
    guard rect.width > 0, rect.height > 0 else {
        return bounds.center
    }
    return rect.clamping(p)
}

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
    /// The zone's local "up" in screen coordinates.
    public var up = Vec2(0, -1)
    /// The player's control zone; the pad is clamped to stay fully inside.
    public var bounds: Rect?

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
        // The d-pad's origin STAYS PUT where the thumb first landed — gas /
        // brake / left / right keep fixed screen positions. (Casual's stick
        // trails the thumb, which suits constant re-aiming; here it'd creep:
        // holding gas without braking would drag the pad ever upward.) The
        // knob just clamps to the rim.
        let offset = location - origin
        let distance = offset.length
        knob = distance > radius ? offset * (radius / distance) : offset
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
    /// Steer ramp for the REVERSE maneuver: full lock once the target is
    /// this many radians off the tail.
    public var fullSteerError = Double.pi / 3
    /// The forward arc: a target within this much of the nose is chased
    /// forwards, anything outside it (the rear 60° either side) is reversed
    /// toward. 120° leaves a rear wedge a thumb can actually hold — the old
    /// rule needed a near-perfect 180° to keep reversing.
    public var reverseThreshold = Double.pi * 2 / 3
    /// A running reverse gives up only once the aim comes this close to the
    /// nose — inside `reverseThreshold`, so entering and leaving can't chatter
    /// on the boundary while the maneuver itself rotates the car.
    public var releaseThreshold = Double.pi / 2
    /// Below this speed (units/s) a behind-target reverses toward it; at
    /// speed the body flips instead — reversing is a parking-lot move.
    public var reverseBelowSpeed = 90.0
    /// How much the gas eases off as the aim swings away from the nose,
    /// 0…1 of the commitment at a full 180°. Low: flips want throttle held
    /// through the drift.
    public var throttleEase = 0.25
    /// The player's control zone; the stick is clamped to stay inside.
    public var bounds: Rect?

    /// Where the stick materialized; nil while not touching.
    public private(set) var origin: Vec2?
    /// Clamped offset of the thumb from `origin`.
    public private(set) var knob = Vec2.zero

    private var activeTouch: TouchID?
    private var carHeading = 0.0
    private var carSpeed = 0.0
    private var carForwardSpeed = 0.0
    /// Latched for the duration of a reverse, so the rotation it causes cannot
    /// re-open the forward/reverse decision mid-maneuver.
    private var isReversing = false

    public init() {}

    public func setCar(heading: Double, forwardSpeed: Double, speed: Double) {
        carHeading = heading
        carForwardSpeed = forwardSpeed
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
        isReversing = false
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard origin != nil, knob.length > deadzone else {
            isReversing = false
            return .coast
        }
        // The thumb offset is a SCREEN-space vector, and the renderer draws
        // the world with no y-flip, so a screen direction IS a world
        // direction — the aimed heading is just the knob's angle. (Unlike
        // the d-pad, `up` doesn't enter: you point at an absolute spot on
        // screen, wherever you're seated.)
        let desired = atan2(knob.y, knob.x)
        let error = atan2(sin(desired - carHeading), cos(desired - carHeading))

        // How committed the push is scales the pace (a light touch eases).
        let commitment = min(1, (knob.length - deadzone) / (radius - deadzone))
        // **The rear wedge reverses; the tail swings all the way to the thumb.**
        // Past `reverseThreshold` off the nose the car backs up, steering to
        // bring its tail around onto the thumb — "aim its butt at the finger".
        //
        // The subtlety is that this maneuver ROTATES THE HEADING the gate is
        // judged against, so a gate re-tested from scratch every tick cancels
        // the very turn it just asked for. Two wrong shapes, both measured:
        //
        //   plain re-test    the tail swings past the thumb and keeps going
        //                    into a full three-point turn, ending with the nose
        //                    on the thumb: 41 ticks at aim 170°, 12 at 130°,
        //                    and only a perfect 180° held. Reported as "it
        //                    tries to flip almost immediately".
        //   fade at the edge steering died at exactly the wedge boundary, so
        //                    the car parked 25° short of the thumb and stopped
        //                    rotating. Reported from a screenshot: backing
        //                    north with the thumb NE, not turning.
        //
        // So the maneuver LATCHES. Once reversing, it stays in reverse and
        // keeps steering until the tail is actually on the thumb — `offTail`
        // itself is the error being driven to zero, which is a stable target
        // because it shrinks as the car turns. It releases only when the player
        // brings the thumb back around the nose (`releaseThreshold`, inside the
        // wedge boundary so the two can't chatter), or on lifting the thumb.
        //
        // Forward speed is SIGNED, so a car already going backwards is never
        // "too fast to flip" — it has nothing to flip.
        let offTail = atan2(sin(desired - carHeading + .pi), cos(desired - carHeading + .pi))
        let stayInReverse = isReversing && abs(error) > releaseThreshold
        if stayInReverse || (abs(error) > reverseThreshold && carForwardSpeed < reverseBelowSpeed) {
            isReversing = true
            // Reversing MIRRORS the wheel — the tail swings opposite the way the
            // nose would — so chasing the thumb with the tail needs the negated
            // error. With the sign the other way the tail turned AWAY from the
            // thumb (measured: `offTail` growing 45°→112°), which both failed to
            // aim the butt anywhere useful and, for a thumb held straight back,
            // showed up as "it tries to turn a little instead of going straight
            // backwards". Zero exactly when the tail already points at the thumb.
            let steer = max(-1, min(1, -offTail / fullSteerError))
            return CarInput(steer: steer, throttle: -commitment)
        }
        isReversing = false
        // Hand the aim to the sim — the body-flip lives in the physics.
        // The gas eases a touch as the aim swings away from the nose, but
        // stays largely on: the flip wants throttle held through the drift.
        let throttle = commitment * (1 - throttleEase * min(1, abs(error) / .pi))
        return CarInput(throttle: throttle, aim: desired)
    }
}
