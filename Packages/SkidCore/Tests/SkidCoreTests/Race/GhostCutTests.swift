import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Cutting the finish-line ghost is a slice, not a replay.** The cut used to
/// re-simulate the race from tick zero to the best lap's start, on the main
/// thread, on the frame the finish line was crossed — measured at 3.4 seconds
/// for a four-car three-lap race in a debug build, felt as "a little pause when
/// reaching the finish line". The session now captures the field's pose at each
/// lap boundary as it passes, and the cut looks its start up by tick.
final class GhostCutTests: XCTestCase {
    /// One recorded run plus the poses a live session would have captured.
    private struct Run {
        var recording: RaceRecording
        var poses: [Tick: LapGhost.Start]
        var lapTimes: [Tick]
        var config: RaceConfig
        var track: Track
    }

    private func makeRun() -> Run {
        let track = TrackLibrary.track(id: "clover")
        let players = (0..<4).map(PlayerID.init)
        let config = RaceConfig(laps: 3, countdownTicks: 180)
        var race = Race(track: track, players: players, seed: 1, config: config)
        var recording = RaceRecording(seed: 1, players: players)
        // Plausible lap boundaries; what matters is that the poses are captured
        // at exactly the ticks `bestLapRange` will compute from them.
        let lapTimes: [Tick] = [800, 780, 760]
        var boundaries: Set<Tick> = [config.countdownTicks]
        var at = config.countdownTicks
        for lap in lapTimes {
            at += lap
            boundaries.insert(at)
        }
        var poses: [Tick: LapGhost.Start] = [:]
        for tick in 0..<2600 {
            let aim = Double(tick % 240) / 240 * 6.28
            let inputs = Dictionary(
                uniqueKeysWithValues: players.map { ($0, CarInput(throttle: 1, aim: aim)) })
            recording.append(inputs)
            race.advance(inputs: inputs)
            if boundaries.contains(race.tick) {
                poses[race.tick] = LapGhost.Start(
                    tick: race.tick,
                    cars: race.cars.map { LapGhost.CarPose(seat: $0.id, state: $0.state) })
            }
        }
        return Run(
            recording: recording, poses: poses, lapTimes: lapTimes, config: config,
            track: track)
    }

    /// The sliced cut is bit-identical to the replayed one — determinism is the
    /// whole reason a live-captured pose can stand in for the replay's state.
    func testThePoseCutMatchesTheReplayCut() {
        let run = makeRun()
        let replayed = run.recording.bestLapGhost(
            on: run.track, lapTimes: run.lapTimes, config: run.config)
        let sliced = run.recording.bestLapGhost(
            on: run.track, lapTimes: run.lapTimes, config: run.config,
            startPoses: run.poses)
        XCTAssertNotNil(replayed)
        XCTAssertEqual(sliced, replayed, "the sliced ghost differs from the replayed one")
    }

    /// And it is fast — the whole point. Generous bound: the replay took
    /// thousands of milliseconds; the slice should take low single digits.
    func testThePoseCutIsQuick() {
        let run = makeRun()
        let start = Date()
        _ = run.recording.bestLapGhost(
            on: run.track, lapTimes: run.lapTimes, config: run.config,
            startPoses: run.poses)
        let ms = Date().timeIntervalSince(start) * 1000
        XCTAssertLessThan(ms, 200, "the cut re-simulated: \(Int(ms)) ms")
    }

    /// The session captures the boundary poses itself, at the ticks the cut
    /// will ask for — the wiring, end to end on a real driven race.
    @MainActor
    func testTheSessionCapturesLapBoundaries() {
        let track = TrackLibrary.track(id: "oval")
        var ai = AIDriver()
        let session = GameSession(
            track: track, players: [PlayerID(0)],
            config: RaceConfig(laps: 2, countdownTicks: 60), seed: 7,
            inputFor: { _, race in ai.input(car: race.cars[0].state, track: track) })
        session.started = true
        var time = 0.0
        while session.race.cars[0].progress.finishedAt == nil, time < 240 {
            time += 1.0 / 30
            session.advance(to: time)
        }
        let car = session.race.cars[0]
        XCTAssertNotNil(car.progress.finishedAt, "the AI never finished — fixture issue")
        // One pose per boundary: the countdown's end plus each completed lap.
        XCTAssertEqual(session.lapStartPoses.count, 1 + car.progress.lapTimes.count)
        // **Every boundary key must be EXACTLY where the lap arithmetic points** —
        // asserting only the count (as this test used to) stayed green when the
        // poses were keyed one tick late, because the cut silently replayed and
        // produced an equal ghost. That was the finish-line hitch, shipped twice.
        var boundary = session.race.config.countdownTicks
        XCTAssertNotNil(session.lapStartPoses[boundary], "lap 1's start pose missing")
        for (lap, ticks) in car.progress.lapTimes.enumerated() {
            boundary += ticks
            XCTAssertNotNil(
                session.lapStartPoses[boundary],
                "lap \(lap + 2)'s start pose missing at tick \(boundary): "
                    + "captured \(session.lapStartPoses.keys.sorted())")
        }
        // And the sliced cut is bit-identical to the replayed one.
        let withPoses = session.recording.bestLapGhost(
            on: track, lapTimes: car.progress.lapTimes, config: session.race.config,
            startPoses: session.lapStartPoses)
        let replayed = session.recording.bestLapGhost(
            on: track, lapTimes: car.progress.lapTimes, config: session.race.config)
        XCTAssertNotNil(withPoses)
        XCTAssertEqual(withPoses, replayed)
    }
}
