import Foundation

/// One engine's target, as the mix hands it to the render thread.
struct EngineTone: Equatable {
    var hz: Double
    var duty: Double
    var gain: Double
}

/// **Every car's engine, one sample at a time.**
///
/// The render block used to hold one voice's state in loose `var`s; a grid of
/// them is a bank. Each voice keeps its own smoothing (pitch and gain changes
/// stay click-free per car), its own starting phase (a golden-ratio spread, so
/// identical pitches never sum coherently into one loud engine), and its own
/// slow wobble — a per-voice flutter at deliberately unrelated rates, so a
/// grid idling at the same speed shimmers like several machines instead of
/// singing in unison. The wobble is deterministic per seat but never enters
/// the sim: sound is render-side, so replays and lockstep are untouched.
struct EngineBank {
    struct Voice {
        var phase: Double
        var subPhase: Double
        var hz = EngineVoice.idleHz
        var duty = 0.3
        var gain = 0.0
        var wobblePhase: Double
        var wobbleHz: Double
    }

    static let maxVoices = 9
    private var voices: [Voice]

    init() {
        voices = (0..<Self.maxVoices).map { i in
            let spread = (Double(i) * 0.381_966).truncatingRemainder(dividingBy: 1)
            return Voice(
                phase: spread, subPhase: spread * 0.5,
                wobblePhase: spread,
                // 0.7…1.9 Hz, no two alike and none a multiple of another.
                wobbleHz: 0.7 + Double(i) * 0.137)
        }
    }

    /// One summed sample of every active engine.
    mutating func sample(targets: [EngineTone], rate: Double) -> Double {
        var sum = 0.0
        for i in voices.indices {
            let target = i < targets.count ? targets[i] : EngineTone(hz: 0, duty: 0.3, gain: 0)
            var voice = voices[i]
            voice.hz += (target.hz - voice.hz) * 0.0004
            voice.duty += (target.duty - voice.duty) * 0.0004
            voice.gain += (target.gain - voice.gain) * 0.0008
            if voice.gain > 0.0004 {
                // The flutter: a few tenths of a percent of pitch, slowly.
                voice.wobblePhase += voice.wobbleHz / rate
                voice.wobblePhase -= voice.wobblePhase.rounded(.down)
                let wobble = 1 + 0.006 * sin(voice.wobblePhase * 2 * .pi)
                voice.phase += voice.hz * wobble / rate
                voice.subPhase += voice.hz * wobble * 0.5 / rate
                voice.phase -= voice.phase.rounded(.down)
                voice.subPhase -= voice.subPhase.rounded(.down)
                sum +=
                    EngineVoice.sample(
                        phase: voice.phase, subPhase: voice.subPhase, duty: voice.duty)
                    * voice.gain
            }
            voices[i] = voice
        }
        return sum
    }
}
