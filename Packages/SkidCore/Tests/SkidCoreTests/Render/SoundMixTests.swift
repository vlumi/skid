import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The mix every car feeds, as pure arithmetic** — reported: only P1's
/// engine sounded, and a finished car's engine kept running after it stopped.
/// `engineTones` is the seam the render thread consumes, so what these pin is
/// what plays.
@MainActor
final class SoundMixTests: XCTestCase {
    private func race(cars: Int) -> Race {
        let track = Track(
            centerline: [Vec2(-10000, 0), Vec2(10000, 0)],
            width: 600,
            gates: [Gate(from: Vec2(400, -300), to: Vec2(400, 300), forward: Vec2(1, 0))],
            startSlots: (0..<cars).map { Vec2(0, Double($0) * 80 - 100) },
            size: Vec2(20000, 4000)
        )
        return Race(
            track: track, players: (0..<cars).map { PlayerID($0) },
            config: RaceConfig(laps: 1))
    }

    /// **Every car is voiced, not just P1** — and each at its own pitch.
    func testEveryCarGetsAVoiceAtItsOwnPitch() {
        var r = race(cars: 4)
        // Give the cars different speeds: only car 0 and 2 accelerate.
        for _ in 0..<60 {
            r.advance(inputs: [
                PlayerID(0): CarInput(throttle: 1), PlayerID(2): CarInput(throttle: 0.5),
            ])
        }
        let tones = SoundEngine.engineTones(race: r)
        XCTAssertEqual(tones.count, 4)
        for tone in tones {
            XCTAssertGreaterThan(tone.gain, 0, "an unfinished car went silent")
        }
        XCTAssertGreaterThan(
            tones[0].hz, tones[1].hz,
            "the moving car should rev above the parked one")
        // Parked cars at identical speed still differ by their seat's detune.
        XCTAssertNotEqual(tones[1].hz, tones[3].hz, "seats must not sing in unison")
    }

    /// **A finished car's engine turns off.** The sim locks it to a stop; the
    /// sound stops with it.
    func testAFinishedCarIsMuted() {
        var r = race(cars: 2)
        var mutedAfterFinish = false
        for _ in 0..<(20 * Race.tickRate) {
            r.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
            if r.cars[0].progress.finishedAt != nil {
                let tones = SoundEngine.engineTones(race: r)
                XCTAssertEqual(tones[0].gain, 0, "the flag did not kill the engine")
                XCTAssertGreaterThan(tones[1].gain, 0, "the still-racing car went quiet too")
                mutedAfterFinish = true
                break
            }
        }
        XCTAssertTrue(mutedAfterFinish, "fixture: car 0 never finished")
    }

    /// The grid shares a gain budget: nine engines are a field, not nine times
    /// the volume of one.
    func testGainIsBudgetedAcrossTheGrid() {
        var solo = race(cars: 1)
        var grid = race(cars: 4)
        for _ in 0..<60 {
            solo.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
            grid.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
        }
        let one = SoundEngine.engineTones(race: solo)[0].gain
        let many = SoundEngine.engineTones(race: grid)
        XCTAssertLessThan(many[0].gain, one, "a grid must dilute each voice")
        let total = many.map(\.gain).reduce(0, +)
        XCTAssertLessThan(total, one * 3, "four engines should not be four times one")
    }

    /// Every seat's detune is distinct, near true pitch, and seat 0 IS true.
    func testDetunesAreDistinctAndGentle() {
        let detunes = (0..<EngineBank.maxVoices).map { EngineVoice.detune(seat: $0) }
        XCTAssertEqual(detunes[0], 1.0)
        XCTAssertEqual(Set(detunes).count, detunes.count, "two seats share a voice")
        for d in detunes {
            XCTAssertGreaterThan(d, 0.9)
            XCTAssertLessThan(d, 1.1)
        }
    }

    /// Skid feedback belongs to the humans at this device — an AI's drift on
    /// the far side of the map is not feedback.
    func testSkidListensToHumansOnly() {
        var r = race(cars: 2)
        // Car 1 (the AI seat when humanCount is 1) corners hard; car 0 idles.
        for _ in 0..<120 {
            r.advance(inputs: [PlayerID(1): CarInput(steer: 1, throttle: 1)])
        }
        XCTAssertEqual(SoundEngine.skidGain(race: r, humanCount: 1), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(SoundEngine.skidGain(race: r, humanCount: 2), 0)
    }
}
