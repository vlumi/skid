import Foundation
import SkidCore

/// **The engine's voice: one sample at a time, and nothing else.**
///
/// Pulled out of `SoundEngine`'s render block so the same arithmetic can run somewhere
/// you can actually *hear* it — see `skid-audio`, which renders these samples to a WAV.
/// A probe that synthesized its own approximation would prove nothing about the game's
/// sound; this is the game's sound, called from a second place.
///
/// **A pulse wave, not the two detuned saws it replaces.** Saws are smooth and read as a
/// synth pad; a pulse train is what a small engine actually is — a rough, buzzy pressure
/// wave — and it is what a 90s PC racer would have produced, which is the look the rest
/// of the game now wears.
///
/// Two things carry the sense of speed, because pitch alone did not:
///
/// - **Duty cycle opens up with load.** A narrow pulse (12%) is thin and nasal; a square
///   (50%) is fat and loud. Sweeping between them makes the engine *strain* as it climbs,
///   which is most of what "revving" sounds like.
/// - **Range.** The old mapping spanned 55→119 Hz over the whole speed range — barely an
///   octave, so nothing ever changed much. This spans over two.
///
/// **Scaled against the car's real top speed, and curved.** The first version mapped its
/// whole range over 0…200 units/s while `CarTuning.maxSpeed` is **520** — measured on a
/// clover lap, the median speed is 482, so the engine sat pinned at redline with the duty
/// cycle wide open for most of a lap and never sounded like it climbed. Reported from
/// device as "it enters the high revs too early".
///
/// The curve is the other half. Linear against 520 would still spend the middle of the
/// range on speeds a lap barely visits; an exponent above 1 keeps the top of the rev
/// range for the top of the speed range — half speed reaches under a third of the pitch
/// climb, and the last stretch to flat out is where it screams.
public struct EngineVoice {
    /// Where the pulse sits at rest, in Hz.
    public static let idleHz = 55.0
    /// …and flat out. Two-plus octaves up, so the climb is audible.
    public static let redlineHz = 260.0

    /// How late the revs arrive. Above 1, so the top of the rev range belongs to the top
    /// of the speed range rather than to the middle of it.
    private static let curve = 1.7

    /// **Each seat's engine sits a hair off true pitch** — a fixed few-percent
    /// detune per grid slot, so a full grid at the same speed is a chorus
    /// rather than one loud engine. Deterministic on purpose: a car keeps its
    /// voice for the whole race, and seat 0 stays exactly on pitch.
    public static func detune(seat: Int) -> Double {
        let offsets = [1.0, 0.968, 1.034, 0.947, 1.052, 0.982, 1.021, 0.958, 1.041]
        return offsets[((seat % offsets.count) + offsets.count) % offsets.count]
    }

    /// How far up the rev range a speed sits, 0…1 — the shared curve, so pitch and duty
    /// cannot drift apart.
    static func revs(forSpeed speed: Double, topSpeed: Double = CarTuning().maxSpeed) -> Double {
        guard topSpeed > 0 else { return 0 }
        let fraction = min(1, max(0, speed / topSpeed))
        return pow(fraction, curve)
    }

    /// Engine pitch for a car's speed, in world units per second.
    public static func hz(forSpeed speed: Double, topSpeed: Double = CarTuning().maxSpeed)
        -> Double
    {
        idleHz + (redlineHz - idleHz) * revs(forSpeed: speed, topSpeed: topSpeed)
    }

    /// Pulse width for a car's speed, 0…1. Narrow and nasal at idle, square at full.
    public static func duty(forSpeed speed: Double, topSpeed: Double = CarTuning().maxSpeed)
        -> Double
    {
        0.12 + 0.38 * revs(forSpeed: speed, topSpeed: topSpeed)
    }

    /// One sample of the engine at `phase`, given its duty cycle.
    ///
    /// The pulse is paired with a square an octave down at a third of the level: the
    /// pulse alone is thin on a phone speaker, which has no low end to speak of, and the
    /// sub is what stops it sounding like a wasp.
    public static func sample(phase: Double, subPhase: Double, duty: Double) -> Double {
        let pulse = phase < duty ? 1.0 : -1.0
        let sub = subPhase < 0.5 ? 1.0 : -1.0
        return pulse * 0.7 + sub * 0.3
    }
}
