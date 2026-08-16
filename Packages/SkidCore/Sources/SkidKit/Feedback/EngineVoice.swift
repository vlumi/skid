import Foundation

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
public struct EngineVoice {
    /// Where the pulse sits at rest, in Hz.
    public static let idleHz = 55.0
    /// …and flat out. Two-plus octaves up, so the climb is audible.
    public static let redlineHz = 260.0

    /// Engine pitch for a car's speed. `speed` is world units per second, as the sim
    /// reports it; ~200 is roughly flat out on the stock car.
    public static func hz(forSpeed speed: Double) -> Double {
        let fraction = min(1, max(0, speed / 200))
        return idleHz + (redlineHz - idleHz) * fraction
    }

    /// Pulse width for a car's speed, 0…1. Narrow and nasal at idle, square at full.
    public static func duty(forSpeed speed: Double) -> Double {
        let fraction = min(1, max(0, speed / 200))
        return 0.12 + 0.38 * fraction
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
