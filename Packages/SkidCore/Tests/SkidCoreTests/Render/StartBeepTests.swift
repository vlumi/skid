import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The countdown's beeps: three counting blips, then a different one on go.**
///
/// The property that matters is "exactly once per second boundary". The audio frame runs
/// at display rate, so anything shaped like "is the clock near a second?" fires the same
/// beep on every frame it is near one — a machine-gun countdown.
final class StartBeepTests: XCTestCase {
    /// **A beep only where the second actually changes.** Same value in, nothing out.
    func testNoBeepWhileTheSecondHoldsSteady() {
        for seconds in 1...3 {
            XCTAssertNil(
                StartBeeps.beep(secondsBefore: seconds, secondsAfter: seconds),
                "\(seconds)s → \(seconds)s beeped, so it would beep every frame")
        }
    }

    /// **Counting down beeps, and they are the ordinary blip.**
    func testCountingBoundariesBeep() {
        XCTAssertEqual(StartBeeps.beep(secondsBefore: 3, secondsAfter: 2), false)
        XCTAssertEqual(StartBeeps.beep(secondsBefore: 2, secondsAfter: 1), false)
    }

    /// **The start is the FINAL beep** — the different one, so "go" does not sound like
    /// a fourth count.
    func testTheStartIsTheFinalBeep() {
        XCTAssertEqual(StartBeeps.beep(secondsBefore: 1, secondsAfter: 0), true)
        // The phase leaves `.countdown` entirely on the same frame — same event.
        XCTAssertEqual(StartBeeps.beep(secondsBefore: 1, secondsAfter: nil), true)
    }

    /// **Nothing beeps once the race is running**, however many frames go by.
    func testNoBeepsDuringTheRace() {
        XCTAssertNil(StartBeeps.beep(secondsBefore: nil, secondsAfter: nil))
        XCTAssertNil(StartBeeps.beep(secondsBefore: 0, secondsAfter: nil))
        XCTAssertNil(StartBeeps.beep(secondsBefore: 0, secondsAfter: 0))
    }

    /// **A whole countdown produces exactly three beeps**, in order, driven tick by tick
    /// through a real race — the end-to-end version of the property above.
    ///
    /// Three, not four: the countdown *starts* at 3, so there is no boundary into it.
    /// What you hear is 3→2, 2→1, and go — which is also what the gantry shows, since
    /// its first state is already on screen when the countdown begins.
    func testARealCountdownBeepsThreeTimes() {
        let track = TrackLibrary.track(id: "clover")
        var race = Race(
            track: track, players: [PlayerID(0)], seed: 1,
            config: RaceConfig(laps: 3, countdownTicks: 3 * Race.tickRate))
        var beeps: [Bool] = []
        var previous = StartBeeps.secondsRemaining(in: race)
        // Well past the start, so a stray late beep would show up too.
        for _ in 0..<(Race.tickRate * 4) {
            race.advance(inputs: [PlayerID(0): .coast])
            let now = StartBeeps.secondsRemaining(in: race)
            if let isFinal = StartBeeps.beep(secondsBefore: previous, secondsAfter: now) {
                beeps.append(isFinal)
            }
            previous = now
        }
        XCTAssertEqual(
            beeps, [false, false, true],
            "expected two counting beeps and one start beep, got \(beeps)")
    }

    /// The seconds shown match the gantry's, so a beep lands on the light it belongs to.
    func testSecondsRoundUpLikeTheLights() {
        let track = TrackLibrary.track(id: "clover")
        let race = Race(
            track: track, players: [PlayerID(0)], seed: 1,
            config: RaceConfig(laps: 3, countdownTicks: 3 * Race.tickRate))
        XCTAssertEqual(StartBeeps.secondsRemaining(in: race), 3)
    }
}
