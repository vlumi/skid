import Foundation

/// **The countdown's voice: a beep, not a bell.**
///
/// The first version was a pure sine fading continuously over 0.4s from the moment it
/// started, which is a struck bell — reported from device as exactly that. Two things
/// made it one, and both are fixed here:
///
/// - **No harmonics.** A sine is the one waveform with nothing above its fundamental, so
///   it reads as soft and rung rather than electronic. This is a *soft* pulse instead:
///   enough harmonic content to sound like a signal, well short of the engine's raw
///   square, because the countdown should not be as rough as the thing it counts down.
/// - **No sustain.** A beep holds and then stops; a bell starts loud and rings away.
///   The envelope is now flat for most of its length with a short fade at each end —
///   long enough to read as a tone, short enough to stay a blip.
///
/// ```text
///   bell (before)   ▁▇▆▅▄▃▂▁▁▁      struck, then ringing away
///   beep (now)      ▁▇▇▇▇▇▇▂▁       held, then cut
/// ```
public struct BeepVoice {
    /// A beep in flight: where its oscillator is, and how far through it we are.
    ///
    /// Grouped rather than five loose `var`s in the render block, which is where they
    /// started — the block is at its length limit and the beep is one idea, not five.
    public struct Playing {
        public init() {}

        public var phase = 0.0
        var hz = 880.0
        var gain = 0.0
        var elapsed = 0.0
        var length = 0.0

        /// Begin a beep, restarting whatever was sounding.
        public mutating func start(hz: Double, gain: Double, rate: Double) {
            self.hz = hz
            self.gain = gain
            phase = 0
            elapsed = 0
            length = BeepVoice.duration * rate
        }

        /// One sample, advancing the oscillator and the position within the beep.
        /// Silent once the beep has run its length.
        public mutating func sample(rate: Double) -> Double {
            guard length > 0, elapsed < length else { return 0 }
            phase += hz / rate
            phase -= phase.rounded(.down)
            elapsed += 1
            return BeepVoice.wave(phase: phase)
                * BeepVoice.envelope(progress: elapsed / length) * gain * 0.35
        }
    }

    /// How long a beep sounds, in seconds.
    ///
    /// Lengthened from 0.18 on the first listen: long enough now to read as a deliberate
    /// tone rather than a blip, and still well inside the one-second gap between lights,
    /// so the beeps stay separated — the silence between them is what makes four of them
    /// countable rather than a warble.
    public static let duration = 0.28

    /// Fraction of the beep spent fading in and out. A hard edge on a square-ish wave
    /// clicks; this is just enough ramp to avoid that without becoming a swell.
    private static let edge = 0.12

    /// The envelope at `progress` (0…1 through the beep): ramp up, hold, ramp down.
    ///
    /// The hold is the whole point. A multiplicative decay — `env *= 0.9999` per sample —
    /// is a bell however you tune it, because it is loudest at the attack and quieter
    /// every sample after.
    public static func envelope(progress: Double) -> Double {
        guard progress >= 0, progress <= 1 else { return 0 }
        if progress < edge { return progress / edge }
        if progress > 1 - edge { return (1 - progress) / edge }
        return 1
    }

    /// One sample of the beep's waveform.
    ///
    /// A pulse at 30% duty, softened by mixing in its own fundamental sine: the pulse
    /// supplies the harmonics that make it read as electronic, the sine takes the harshest
    /// edge off. Deliberately between the engine's square and the old bare sine.
    public static func wave(phase: Double) -> Double {
        let pulse = phase < 0.3 ? 1.0 : -1.0
        let sine = sin(phase * 2 * .pi)
        return pulse * 0.55 + sine * 0.45
    }
}
