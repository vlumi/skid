import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The countdown's voice: a beep, not a bell.**
///
/// Reported from device as "weird bells", and two things made it one — a pure sine (no
/// harmonics) and a continuous decay from the first sample. Both are properties, so both
/// are pinned here rather than left to an ear nobody has on the simulator.
final class BeepVoiceTests: XCTestCase {
    /// **It holds.** The bell quality was a multiplicative decay: loudest at the attack
    /// and quieter every sample after. A beep is flat in the middle.
    func testTheEnvelopeHoldsRatherThanDecaying() {
        // Sampled across the middle, away from the ramps at either end.
        let middle = stride(from: 0.2, through: 0.8, by: 0.05)
            .map { BeepVoice.envelope(progress: $0) }
        for value in middle {
            XCTAssertEqual(value, 1.0, accuracy: 1e-9, "the beep decays instead of holding")
        }
    }

    /// It ramps at both ends — a hard edge on a square-ish wave clicks.
    func testItRampsInAndOut() {
        XCTAssertEqual(BeepVoice.envelope(progress: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(BeepVoice.envelope(progress: 1), 0, accuracy: 1e-9)
        XCTAssertLessThan(BeepVoice.envelope(progress: 0.02), 1)
        XCTAssertLessThan(BeepVoice.envelope(progress: 0.98), 1)
        XCTAssertGreaterThan(BeepVoice.envelope(progress: 0.02), 0)
    }

    /// **Symmetric ramps**, so the beep does not sound like it leans one way.
    func testTheRampsMatch() {
        for offset in [0.02, 0.05, 0.1] {
            XCTAssertEqual(
                BeepVoice.envelope(progress: offset),
                BeepVoice.envelope(progress: 1 - offset), accuracy: 1e-9)
        }
    }

    /// Nothing sounds outside the beep's own span.
    func testItIsSilentOutsideItsSpan() {
        XCTAssertEqual(BeepVoice.envelope(progress: -0.1), 0, accuracy: 1e-9)
        XCTAssertEqual(BeepVoice.envelope(progress: 1.5), 0, accuracy: 1e-9)
    }

    /// **It has harmonics**, which is the other half of not being a bell: a sine is the
    /// one waveform with nothing above its fundamental. Asymmetry over the cycle is the
    /// cheap proxy — a sine spends exactly half its cycle positive, a pulse does not.
    func testTheWaveIsNotASine() {
        let samples = (0..<1000).map { BeepVoice.wave(phase: Double($0) / 1000) }
        let positive = Double(samples.filter { $0 > 0 }.count) / 1000
        XCTAssertLessThan(
            positive, 0.45, "the beep is spending a sine's half-cycle high — no harmonics")
    }

    /// The waveform stays in range, so the mix's headroom budget holds.
    func testTheWaveStaysWithinUnitRange() {
        for step in 0..<1000 {
            XCTAssertLessThanOrEqual(abs(BeepVoice.wave(phase: Double(step) / 1000)), 1.0)
        }
    }

    /// **A beep ends, and stays ended.** Two guards enforce this — the elapsed check in
    /// `sample` and the envelope returning zero past its span — so this drives it far
    /// enough past the end that a broken one would be audibly wrong, not just one sample
    /// out. (Removing the elapsed guard alone still passes: the envelope covers it. That
    /// redundancy is deliberate; a beep that never stops is the worst failure here.)
    func testABeepStopsAfterItsDuration() {
        let rate = 48_000.0
        var beep = BeepVoice.Playing()
        beep.start(hz: 660, gain: 1, rate: rate)
        let length = Int(BeepVoice.duration * rate)
        var loudest = 0.0
        for _ in 0..<length {
            loudest = max(loudest, abs(beep.sample(rate: rate)))
        }
        XCTAssertGreaterThan(loudest, 0.1, "the beep never made a sound")
        // A full second past the end — a beep that kept sounding would drone under the
        // whole race.
        for _ in 0..<Int(rate) {
            XCTAssertEqual(beep.sample(rate: rate), 0, accuracy: 1e-12)
        }
    }

    /// A fresh, unstarted beep is silent — no click on the first frame of a race.
    func testAnUnstartedBeepIsSilent() {
        var beep = BeepVoice.Playing()
        XCTAssertEqual(beep.sample(rate: 48_000), 0, accuracy: 1e-12)
    }
}
