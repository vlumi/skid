import Foundation
import SkidCore
import SwiftUI

/// Impact taps and a finish flourish, from the same deterministic
/// `RaceEvent` stream the audio uses. iOS only; a no-op elsewhere.
@MainActor
public final class Haptics {
    #if os(iOS)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notice = UINotificationFeedbackGenerator()
    #endif

    public init() {}

    public func play(events: [RaceEvent], humanCount: Int) {
        #if os(iOS)
        for event in events {
            switch event {
            case .wallImpact(let id, let speed) where id.rawValue < humanCount:
                if speed > 200 {
                    heavy.impactOccurred()
                } else {
                    light.impactOccurred()
                }
            case .carImpact(let a, let b, _)
            where a.rawValue < humanCount || b.rawValue < humanCount:
                heavy.impactOccurred(intensity: 0.8)
            case .finished(let id) where id.rawValue < humanCount:
                notice.notificationOccurred(.success)
            default:
                break
            }
        }
        #endif
    }
}

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
    }

    /// The race tuning the dials describe (pace folded in).
    public var carTuning: CarTuning {
        CarTuning(
            turnRate: turnRate,
            aimTurnRate: aimTurnRate,
            aimFlipBoost: aimFlipBoost,
            steerFlipBoost: steerFlipBoost,
            driftRetention: driftRetention,
            gripScale: gripScale
        ).scaled(pace: pace)
    }

    public init() {}
}
