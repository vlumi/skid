import Foundation
import SkidCore
import SwiftUI

/// Player-facing toggles + the control-tuning playground, persisted across
/// launches. The tuning dials exist to be A/B-ed on device before the
/// scheme verdict — they may shrink once the feel is settled.
@MainActor
public final class GameSettings: ObservableObject {
    @AppStorage("skid.sound") public var soundOn = true
    @AppStorage("skid.haptics") public var hapticsOn = true

    // D-pad feel (applied live, every frame).
    @AppStorage("skid.dpad.deadzone") public var dpadDeadzone = 10.0
    @AppStorage("skid.dpad.travel") public var dpadTravel = 48.0
    /// Steps per axis; 0 = fully analog. Analog is the default — on-device
    /// feel testing found it the most natural.
    @AppStorage("skid.dpad.steps") public var dpadSteps = 0
    /// Response curve; 1 = linear, higher = softer near center. A gentle
    /// curve is the default so small corrections stay small.
    @AppStorage("skid.dpad.expo") public var dpadExpo = 1.4

    // Aim scheme feel (applied live, every frame).
    /// Below this speed a behind-target reverses; at speed the body flips.
    @AppStorage("skid.aim.reverseBelowSpeed") public var aimReverseBelowSpeed = 90.0
    /// Gas ease-off toward a full-180 aim, 0…1 of the commitment.
    @AppStorage("skid.aim.throttleEase") public var aimThrottleEase = 0.25
    /// Half-width of the FORWARD arc, in degrees: a thumb further off the nose
    /// than this reverses. Degrees, not radians, because it is the number the
    /// player is reasoning about ("the rear 60° reverses").
    @AppStorage("skid.aim.forwardArcDegrees") public var aimForwardArcDegrees = 150.0
    /// Tail-swing lock: full steer once the tail is this many degrees off the
    /// thumb. Lower swings the tail around harder.
    @AppStorage("skid.aim.tailSwingDegrees") public var aimTailSwingDegrees = 45.0

    // Drift physics dials (applied on Reset, like pace — the sim is fixed
    // for a race). Hiscores only record at the stock values.
    /// Base yaw rate toward the aim, rad/s.
    @AppStorage("skid.sim.aimTurnRate") public var aimTurnRate = 10.0
    /// Extra aim yaw rate at full speed, rad/s (the handbrake inertia).
    @AppStorage("skid.sim.aimFlipBoost") public var aimFlipBoost = 8.0
    /// Steer-path flip assist at full speed, rad/s — the d-pad's drift.
    @AppStorage("skid.sim.steerFlipBoost") public var steerFlipBoost = 5.0
    /// How much of a drift's bled speed is redirected along the nose, 0…1.
    @AppStorage("skid.sim.driftRetention") public var driftRetention = 1.0
    /// Wheel yaw rate at full steer (the classic schemes), rad/s.
    @AppStorage("skid.sim.turnRate") public var turnRate = 3.4
    /// Global grip multiplier — the "inertia": lower = more slide, the car's
    /// motion lags the nose longer.
    @AppStorage("skid.sim.gripScale") public var gripScale = 1.0

    // MARK: - Wall contact
    //
    // Live-tunable because this is pure feel: it was retuned three times from
    // device play, and arithmetic cannot settle it. See `CarTuning`'s wall section
    // for which knob answers which complaint.

    /// Bounce off a wall hit SQUARE ON, 0…1.
    @AppStorage("skid.sim.wallRestitution") public var wallRestitution = 0.40
    /// The bounce a pure glance keeps, as a share of the above. Zero feels dead.
    @AppStorage("skid.sim.wallGlanceBounce") public var wallGlanceBounce = 0.3
    /// How fast a scrape bleeds speed along the wall.
    @AppStorage("skid.sim.wallFriction") public var wallFriction = 0.002
    /// The share of top speed a sustained drag settles at, rather than stopping.
    @AppStorage("skid.sim.wallDragFloor") public var wallDragFloor = 0.1
    /// How hard a hit pulls the nose along the wall.
    @AppStorage("skid.sim.wallYaw") public var wallYaw = 0.012
    /// Downward pull on an airborne car — tunes how a FALL reads, not how far
    /// a jump goes (the launch kick sets that).
    @AppStorage("skid.sim.gravity") public var gravity = 18.0
    /// Upward kick off a launch lip, per unit of speed — sets jump distance.
    @AppStorage("skid.sim.launchPerSpeed") public var launchPerSpeed = 0.004

    /// Game pace for learning: scales acceleration + speed caps (agility
    /// stays). Applies on the next race (Reset). Hiscores only record at
    /// full pace.
    @AppStorage("skid.pace") public var pace = 1.0

    /// How much bigger the road (and a car) gets at full deck height — the one
    /// elevation feel knob, live-tunable so it can be dialed on device. The
    /// renderers read `Elevation.deckScale`; call `applyRenderTuning()` after
    /// changing this to push it there (@AppStorage can't observe reliably).
    /// Purely visual.
    @AppStorage("skid.elevation.deckScale") public var deckScale = 1.2

    /// **Debug overlay**: draws the sim's own view of the world on top of the
    /// race — the centerline, each car's height and surface, and where walls are.
    ///
    /// Worth having as a real feature rather than a scratch probe: the elevation
    /// bugs in this area were all cases of the drawing and the physics disagreeing,
    /// and every one of them was found on device by eye rather than by test.
    /// Seeing what the sim thinks is true, while driving, is the fastest way to
    /// tell those apart. Purely additive — it changes nothing about the sim.
    @AppStorage("skid.debug.overlay") public var debugOverlay = false

    /// Push the live-tunable render knobs into their global sinks. Call at
    /// startup (persisted value before the first frame) and whenever a knob
    /// changes (the Tuning slider).
    public func applyRenderTuning() {
        Elevation.deckScale = deckScale
    }

    /// Whether the physics dials sit at their stock values — recordings
    /// (hiscores, ghosts) replay with stock tuning, so only stock runs
    /// count. Mirrors the full-pace rule.
    public var isStockPhysics: Bool {
        let stock = CarTuning()
        return abs(aimTurnRate - stock.aimTurnRate) < 1e-9
            && abs(aimFlipBoost - stock.aimFlipBoost) < 1e-9
            && abs(steerFlipBoost - stock.steerFlipBoost) < 1e-9
            && abs(driftRetention - stock.driftRetention) < 1e-9
            && abs(turnRate - stock.turnRate) < 1e-9
            && abs(gripScale - stock.gripScale) < 1e-9
            && abs(wallRestitution - stock.wallRestitution) < 1e-9
            && abs(wallGlanceBounce - stock.wallGlanceBounce) < 1e-9
            && abs(wallFriction - stock.wallFriction) < 1e-9
            && abs(wallDragFloor - stock.wallDragFloor) < 1e-9
            && abs(gravity - stock.gravity) < 1e-9
            && abs(launchPerSpeed - stock.launchPerSpeed) < 1e-9
            && abs(wallYaw - stock.wallYaw) < 1e-9
    }

    /// The race tuning the dials describe (pace folded in).
    public var carTuning: CarTuning {
        CarTuning(
            turnRate: turnRate,
            aimTurnRate: aimTurnRate,
            aimFlipBoost: aimFlipBoost,
            steerFlipBoost: steerFlipBoost,
            driftRetention: driftRetention,
            gripScale: gripScale,
            wallRestitution: wallRestitution,
            wallGlanceBounce: wallGlanceBounce,
            wallFriction: wallFriction,
            wallDragFloor: wallDragFloor,
            wallYaw: wallYaw,
            gravity: gravity,
            launchPerSpeed: launchPerSpeed
        ).scaled(pace: pace)
    }

    public init() {}
}
