import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The engine's voice.**
///
/// Nobody involved can hear the simulator, so the properties that make an engine sound
/// like an engine are pinned numerically instead: it climbs, it opens up, and it stays
/// inside the mix. `skid-audio` renders the same code to WAV for the part only ears can
/// judge.
final class EngineVoiceTests: XCTestCase {
    /// **It revs.** The old mapping spanned 55→119 Hz across the whole speed range —
    /// about one octave, which is why it read as a constant hum rather than an engine.
    func testThePitchClimbsMoreThanTwoOctaves() {
        let idle = EngineVoice.hz(forSpeed: 0)
        let flatOut = EngineVoice.hz(forSpeed: 200)
        XCTAssertEqual(idle, EngineVoice.idleHz, accuracy: 1e-9)
        XCTAssertEqual(flatOut, EngineVoice.redlineHz, accuracy: 1e-9)
        XCTAssertGreaterThan(
            log2(flatOut / idle), 2.0,
            "the engine should span more than two octaves; it spans \(log2(flatOut / idle))")
    }

    /// Pitch rises with speed the whole way, with no plateau or fold-back.
    func testPitchRisesMonotonically() {
        var previous = -1.0
        for speed in stride(from: 0.0, through: 260, by: 10) {
            let hz = EngineVoice.hz(forSpeed: speed)
            XCTAssertGreaterThanOrEqual(hz, previous, "pitch fell at speed \(speed)")
            previous = hz
        }
    }

    /// **The pulse opens up** from thin-and-nasal to a full square, which is what makes
    /// it strain rather than just get higher.
    func testTheDutyCycleOpensUpWithSpeed() {
        XCTAssertEqual(EngineVoice.duty(forSpeed: 0), 0.12, accuracy: 1e-9)
        XCTAssertEqual(EngineVoice.duty(forSpeed: 200), 0.50, accuracy: 1e-9)
        XCTAssertLessThan(
            EngineVoice.duty(forSpeed: 50), EngineVoice.duty(forSpeed: 150))
    }

    /// **Beyond flat out is still flat out**, rather than a siren: speeds past the top of
    /// the range clamp instead of climbing forever.
    func testItClampsAboveTheTopSpeed() {
        XCTAssertEqual(
            EngineVoice.hz(forSpeed: 10_000), EngineVoice.redlineHz, accuracy: 1e-9)
        XCTAssertEqual(EngineVoice.duty(forSpeed: 10_000), 0.50, accuracy: 1e-9)
        // And a negative speed (reversing) does not invert the pitch.
        XCTAssertEqual(EngineVoice.hz(forSpeed: -50), EngineVoice.idleHz, accuracy: 1e-9)
    }

    /// **The waveform stays in range**, so the mix has a predictable ceiling to budget
    /// against — the sum of the voices is what decides whether the output clips.
    func testTheWaveformStaysWithinUnitRange() {
        for duty in [0.12, 0.3, 0.5] {
            for step in 0..<200 {
                let phase = Double(step) / 200
                let sample = EngineVoice.sample(
                    phase: phase, subPhase: phase, duty: duty)
                XCTAssertLessThanOrEqual(abs(sample), 1.0, "duty \(duty) phase \(phase)")
            }
        }
    }

    /// A pulse is asymmetric by construction — that asymmetry is the timbre. A duty of
    /// 0.12 spends most of its cycle low; a square splits evenly.
    func testANarrowPulseSpendsMostOfItsCycleLow() {
        func highFraction(duty: Double) -> Double {
            let samples = (0..<1000).map {
                EngineVoice.sample(phase: Double($0) / 1000, subPhase: 0.75, duty: duty)
            }
            return Double(samples.filter { $0 > 0 }.count) / 1000
        }
        XCTAssertLessThan(highFraction(duty: 0.12), highFraction(duty: 0.5))
    }
}
