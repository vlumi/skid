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
        let flatOut = EngineVoice.hz(forSpeed: CarTuning().maxSpeed)
        XCTAssertEqual(idle, EngineVoice.idleHz, accuracy: 1e-9)
        XCTAssertEqual(flatOut, EngineVoice.redlineHz, accuracy: 1e-6)
        XCTAssertGreaterThan(
            log2(flatOut / idle), 2.0,
            "the engine should span more than two octaves; it spans \(log2(flatOut / idle))")
    }

    /// Pitch rises with speed the whole way, with no plateau or fold-back.
    func testPitchRisesMonotonically() {
        var previous = -1.0
        for speed in stride(from: 0.0, through: CarTuning().maxSpeed + 40, by: 10) {
            let hz = EngineVoice.hz(forSpeed: speed)
            XCTAssertGreaterThanOrEqual(hz, previous, "pitch fell at speed \(speed)")
            previous = hz
        }
    }

    /// **The pulse opens up** from thin-and-nasal to a full square, which is what makes
    /// it strain rather than just get higher.
    func testTheDutyCycleOpensUpWithSpeed() {
        XCTAssertEqual(EngineVoice.duty(forSpeed: 0), 0.12, accuracy: 1e-9)
        XCTAssertEqual(
            EngineVoice.duty(forSpeed: CarTuning().maxSpeed), 0.50, accuracy: 1e-6)
        XCTAssertLessThan(
            EngineVoice.duty(forSpeed: 130), EngineVoice.duty(forSpeed: 400))
    }

    /// **Beyond flat out is still flat out**, rather than a siren: speeds past the top of
    /// the range clamp instead of climbing forever.
    func testItClampsAboveTheTopSpeed() {
        XCTAssertEqual(
            EngineVoice.hz(forSpeed: 10_000), EngineVoice.redlineHz, accuracy: 1e-6)
        XCTAssertEqual(EngineVoice.duty(forSpeed: 10_000), 0.50, accuracy: 1e-6)
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

/// **The rev curve: scaled to the car's real top speed, and late-rising.**
///
/// The first version mapped its whole range over 0…200 units/s while `maxSpeed` is 520 —
/// measured, a clover lap's median speed is 482, so the engine sat pinned at redline for
/// most of a lap. Reported from device as reaching the high revs too early.
final class EngineRevCurveTests: XCTestCase {
    /// **Flat out means flat out**, and idle means idle — the ends are still anchored.
    func testTheEndsOfTheRangeAreAnchored() {
        let top = CarTuning().maxSpeed
        XCTAssertEqual(EngineVoice.hz(forSpeed: 0), EngineVoice.idleHz, accuracy: 1e-9)
        XCTAssertEqual(EngineVoice.hz(forSpeed: top), EngineVoice.redlineHz, accuracy: 1e-6)
        XCTAssertEqual(EngineVoice.duty(forSpeed: top), 0.50, accuracy: 1e-6)
    }

    /// **The top of the rev range belongs to the top of the speed range.** Half speed must
    /// sit well under half the climb, which is the whole complaint: linear meant a lap
    /// spent at 90%+ of top speed had nothing left to give.
    func testHalfSpeedIsWellUnderHalfTheRevs() {
        let half = EngineVoice.revs(forSpeed: CarTuning().maxSpeed / 2)
        XCTAssertLessThan(half, 0.4, "half speed reaches \(half) of the rev range — too early")
        XCTAssertGreaterThan(half, 0.15, "…but it should still be audibly climbing")
    }

    /// **A lap's normal speed is not yet redline.** Measured median on the clover is 482
    /// of 520; there has to be headroom above it or the engine is a constant tone.
    func testLapSpeedLeavesHeadroomAboveIt() {
        let atLap = EngineVoice.hz(forSpeed: 482)
        XCTAssertLessThan(
            atLap, EngineVoice.redlineHz - 10,
            "a lap's usual speed is already at redline: nothing left to hear")
        XCTAssertGreaterThan(atLap, 180, "…but it should sound like it is working hard")
    }

    /// It climbs the whole way, with no plateau — a flat stretch would be a speed range
    /// you cannot hear yourself cross.
    func testItClimbsAcrossTheWholeRange() {
        var previous = -1.0
        for speed in stride(from: 0.0, through: CarTuning().maxSpeed, by: 20) {
            let hz = EngineVoice.hz(forSpeed: speed)
            XCTAssertGreaterThan(hz, previous, "the curve plateaus at \(speed)")
            previous = hz
        }
    }

    /// Pitch and duty share one curve, so they cannot drift apart.
    func testPitchAndDutyShareTheCurve() {
        for speed in [0.0, 130, 260, 400, 520] {
            let revs = EngineVoice.revs(forSpeed: speed)
            XCTAssertEqual(
                EngineVoice.hz(forSpeed: speed),
                EngineVoice.idleHz + (EngineVoice.redlineHz - EngineVoice.idleHz) * revs,
                accuracy: 1e-9)
            XCTAssertEqual(
                EngineVoice.duty(forSpeed: speed), 0.12 + 0.38 * revs, accuracy: 1e-9)
        }
    }

    /// A zero or negative top speed cannot divide by zero or inverted-map.
    func testADegenerateTopSpeedIsSafe() {
        XCTAssertEqual(EngineVoice.revs(forSpeed: 100, topSpeed: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(EngineVoice.revs(forSpeed: -100), 0, accuracy: 1e-9)
    }
}
