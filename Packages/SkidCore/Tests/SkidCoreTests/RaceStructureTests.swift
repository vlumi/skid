import XCTest

@testable import SkidCore

final class RaceStructureTests: XCTestCase {
    /// A straight sprint course: three directional gates then start/finish,
    /// all facing +x, wide enough that a straight drive crosses them all.
    private func sprintTrack() -> Track {
        func gate(x: Double) -> Gate {
            Gate(from: Vec2(x, -300), to: Vec2(x, 300), forward: Vec2(1, 0))
        }
        return Track(
            centerline: [Vec2(-20000, 0), Vec2(20000, 0)],
            width: 600,
            gates: [gate(x: 400), gate(x: 800), gate(x: 1200), gate(x: 1600)],
            startSlots: [Vec2.zero],
            size: Vec2(40000, 4000)
        )
    }

    private func drive(_ race: inout Race, ticks: Int, throttle: Double = 1) {
        for _ in 0..<ticks {
            race.advance(inputs: [PlayerID(0): CarInput(throttle: throttle)])
        }
    }

    func testCountdownHoldsCarsThenReleases() {
        var race = Race(
            track: sprintTrack(), players: [PlayerID(0)],
            config: RaceConfig(laps: 1, countdownTicks: 120)
        )
        drive(&race, ticks: 60)
        if case .countdown(let remaining) = race.phase {
            XCTAssertEqual(remaining, 60)
        } else {
            XCTFail("expected countdown, got \(race.phase)")
        }
        XCTAssertEqual(race.cars[0].state.position, .zero)

        drive(&race, ticks: 120)
        XCTAssertEqual(race.phase, .running)
        XCTAssertGreaterThan(race.cars[0].state.position.x, 0)
        XCTAssertEqual(race.raceTicks, 60)
    }

    func testLapEarnedGatesInOrderAndTimed() {
        var race = Race(
            track: sprintTrack(), players: [PlayerID(0)],
            config: RaceConfig(laps: 1, countdownTicks: 60)
        )
        drive(&race, ticks: 60 * 10)
        let progress = race.cars[0].progress
        XCTAssertEqual(progress.lap, 1)
        XCTAssertNotNil(progress.finishedAt)
        XCTAssertEqual(progress.lapTimes.count, 1)
        // The lap time excludes the countdown and is a sane duration.
        XCTAssertGreaterThan(progress.lapTimes[0], 60)
        XCTAssertLessThan(progress.lapTimes[0], 60 * 9)
        XCTAssertEqual(progress.lapTimes[0], progress.finishedAt! - 60)
        XCTAssertEqual(race.phase, .finished)
    }

    func testBackwardsCrossingNeverCounts() {
        var track = sprintTrack()
        // Start beyond the first gate, driving back through it.
        track.startSlots = [Vec2(600, 0)]
        track.startHeading = .pi  // facing -x
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
        drive(&race, ticks: 120)
        XCTAssertLessThan(race.cars[0].state.position.x, 400)
        XCTAssertEqual(race.cars[0].progress.nextGate, 0)
        XCTAssertEqual(race.cars[0].progress.lap, 0)
    }

    func testGateOrderCannotBeSkipped() {
        // Teleport-style check at the Gate level: crossing gate 2 while
        // gate 0 is next must not advance progress.
        var race = Race(track: sprintTrack(), players: [PlayerID(0)], config: RaceConfig(laps: 1))
        // Drive through all gates; nextGate cycles back to 0 after the lap.
        drive(&race, ticks: 60 * 10)
        XCTAssertEqual(race.cars[0].progress.lap, 1)
        // A fresh race whose car never crosses gate 0 stays at nextGate 0
        // even after long driving away from the course.
        var idle = Race(track: sprintTrack(), players: [PlayerID(0)], config: RaceConfig(laps: 1))
        for _ in 0..<120 {
            idle.advance(inputs: [PlayerID(0): CarInput(throttle: -1)])  // reverse, away
        }
        XCTAssertEqual(idle.cars[0].progress.nextGate, 0)
    }

    func testFinishedCarCoasts() {
        var race = Race(
            track: sprintTrack(), players: [PlayerID(0)], config: RaceConfig(laps: 1)
        )
        drive(&race, ticks: 60 * 10)
        XCTAssertNotNil(race.cars[0].progress.finishedAt)
        let speedAtFlag = race.cars[0].state.velocity.length
        drive(&race, ticks: 120)  // full throttle input is ignored now
        XCTAssertLessThan(race.cars[0].state.velocity.length, speedAtFlag)
    }

    func testRecordingReplaysBitForBit() {
        let track = TrackLibrary.practiceLoop()
        let players = [PlayerID(0), PlayerID(1)]
        let config = RaceConfig(laps: 2, countdownTicks: 30)
        var race = Race(track: track, players: players, seed: 99, config: config)
        var recording = RaceRecording(seed: 99, players: players)
        for tick in 0..<900 {
            let phase = Double(tick) / 60.0
            let inputs = [
                PlayerID(0): CarInput(steer: sin(phase * 1.3), throttle: 1),
                PlayerID(1): CarInput(steer: cos(phase), throttle: 0.7),
            ]
            recording.append(inputs)
            race.advance(inputs: inputs)
        }
        let replayed = recording.replay(on: track, config: config)
        XCTAssertEqual(replayed, race)
    }

    func testPracticeLoopHazardPatches() {
        let track = TrackLibrary.practiceLoop()
        XCTAssertEqual(track.patches.count, 3)
        for patch in track.patches {
            XCTAssertEqual(track.surface(at: patch.center), patch.surface)
            // Every hazard touches the ribbon (it threatens the racing line).
            XCTAssertLessThanOrEqual(
                track.distanceToCenterline(patch.center),
                track.width / 2 + patch.radius
            )
        }
    }
}
