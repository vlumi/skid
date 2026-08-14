import Foundation
import Testing

@testable import SkidCore

/// **A lap ghost must drive the line it was cut from.**
///
/// The size win is easy; the correctness is not. A ghost is a slice of a run replayed from
/// a *seeded* race rather than from the start line, so the question these answer is whether
/// the seeding is complete — a missing piece of state shows up as a ghost that drifts off
/// the recorded line within a corner or two.
struct LapGhostTests {
    /// A finished run, and everything a ghost is cut from it with.
    private struct Run {
        var recording: RaceRecording
        var lapTimes: [Tick]
        var config: RaceConfig
        var track: Track
    }

    /// A real run: AI round the clover for three laps.
    private func run(laps: Int = 3, track id: String = "clover") -> Run {
        let track = TrackLibrary.track(id: id)
        let config = RaceConfig(laps: laps)
        var race = Race(track: track, players: [PlayerID(0)], seed: 42, config: config)
        var recording = RaceRecording(seed: 42, players: [PlayerID(0)])
        var ai = AIDriver()
        while race.phase != .finished, recording.inputs.count < 60 * 60 * 4 {
            let input = ai.input(car: race.cars[0].state, track: track)
            recording.append([PlayerID(0): input])
            race.advance(inputs: [PlayerID(0): input])
        }
        return Run(
            recording: recording, lapTimes: race.cars[0].progress.lapTimes,
            config: config, track: track)
    }

    /// The arithmetic, in isolation: laps run back to back after the countdown.
    @Test func theBestLapRangeIsWhereThatLapRan() {
        // Best is lap 2, so it starts after the countdown plus lap 1.
        let range = RaceRecording.bestLapRange(lapTimes: [600, 550, 620], countdownTicks: 180)
        #expect(range == 780..<1330)
        // Best is lap 1: straight after the countdown.
        #expect(RaceRecording.bestLapRange(lapTimes: [500, 600], countdownTicks: 180) == 180..<680)
        // No laps, no ghost.
        #expect(RaceRecording.bestLapRange(lapTimes: [], countdownTicks: 180) == nil)
    }

    /// **The saving is real, and it is the whole point.** A ghost is one lap, not a run.
    @Test func aGhostIsOneLapNotTheWholeRun() throws {
        let run = self.run()
        let (recording, lapTimes, config, track) =
            (run.recording, run.lapTimes, run.config, run.track)
        let ghost = try #require(
            recording.bestLapGhost(on: track, lapTimes: lapTimes, config: config))
        let best = try #require(lapTimes.min())
        #expect(ghost.ticks == best)
        #expect(ghost.inputs.count == Int(best))
        #expect(
            ghost.inputs.count < recording.inputs.count / 2,
            "a 3-lap run's ghost should be far smaller than the run")
    }

    /// **The line is identical**, tick for tick, to the lap inside the original run.
    ///
    /// This is what makes the seeded start trustworthy. Sabotage: skip the seeding in
    /// `Race.seed(from:)` and the ghost drives from the grid instead of from the lap's
    /// start.
    ///
    /// Note what this does NOT catch: dropping `steerActuator` alone leaves the line
    /// unchanged, because the AI's inputs are smooth enough for a straight wheel to catch
    /// up within a tick. It is kept as state that is genuinely live at the boundary, and
    /// a human's sharper steering is where it would show — which the suite cannot drive.
    @Test func aGhostDrivesTheRecordedLine() throws {
        let run = self.run()
        let (recording, lapTimes, config, track) =
            (run.recording, run.lapTimes, run.config, run.track)
        let ghost = try #require(
            recording.bestLapGhost(on: track, lapTimes: lapTimes, config: config))
        let range = try #require(
            RaceRecording.bestLapRange(lapTimes: lapTimes, countdownTicks: config.countdownTicks))

        // What the original run did during that lap.
        var original = Race(
            track: track, players: recording.players, seed: recording.seed, config: config)
        for tickInputs in recording.inputs[..<Int(range.lowerBound)] {
            original.advance(inputs: tickInputs)
        }
        var expected: [Vec2] = []
        for tickInputs in recording.inputs[Int(range.lowerBound)..<Int(range.upperBound)] {
            original.advance(inputs: tickInputs)
            expected.append(original.cars[0].state.position)
        }

        // What the ghost does, replayed from its own snapshot.
        var replay = Race(track: track, players: ghost.players, seed: ghost.seed, config: config)
        replay.seed(from: ghost.start)
        var actual: [Vec2] = []
        for tickInputs in ghost.inputs {
            replay.advance(inputs: tickInputs)
            actual.append(replay.cars[0].state.position)
        }

        #expect(actual.count == expected.count)
        for (index, pair) in zip(actual, expected).enumerated() {
            #expect(pair.0 == pair.1, "the ghost left the recorded line")
            if pair.0 != pair.1 {
                Issue.record("first divergence at tick \(index): \(pair.0) vs \(pair.1)")
                break
            }
        }
    }

    /// A run that completed no laps has no ghost, rather than an empty one.
    @Test func anUnfinishedRunHasNoGhost() {
        let track = TrackLibrary.track(id: "clover")
        let recording = RaceRecording(seed: 1, players: [PlayerID(0)])
        #expect(
            recording.bestLapGhost(on: track, lapTimes: [], config: RaceConfig(laps: 3)) == nil)
    }

    /// A recording that ends before the lap it claims is refused, not sliced past its end.
    @Test func aTruncatedRecordingHasNoGhost() {
        let track = TrackLibrary.track(id: "clover")
        var recording = RaceRecording(seed: 1, players: [PlayerID(0)])
        for _ in 0..<10 { recording.append([PlayerID(0): CarInput(throttle: 1)]) }
        // Claims a 600-tick lap after a 180-tick countdown; only 10 ticks exist.
        #expect(
            recording.bestLapGhost(on: track, lapTimes: [600], config: RaceConfig(laps: 1)) == nil)
    }

    /// Round-trips through JSON, since this is what replaces the stored recording.
    @Test func aGhostSurvivesEncoding() throws {
        let run = self.run()
        let (recording, lapTimes, config, track) =
            (run.recording, run.lapTimes, run.config, run.track)
        let ghost = try #require(
            recording.bestLapGhost(on: track, lapTimes: lapTimes, config: config))
        let data = try JSONEncoder().encode(ghost)
        let back = try JSONDecoder().decode(LapGhost.self, from: data)
        #expect(back == ghost)
    }
}

/// **The packed encoding**, which is what makes a ghost small enough to keep per track.
struct LapGhostPackingTests {
    private func ghost(seats: Int, ticks: Int) -> LapGhost {
        let players = (0..<seats).map { PlayerID($0) }
        var inputs: [[PlayerID: CarInput]] = []
        for tick in 0..<ticks {
            var frame: [PlayerID: CarInput] = [:]
            for (index, seat) in players.enumerated() {
                // **Quantised, as a real ghost's inputs are.** `Race.advance` quantises
                // everything it steps, so a recording holds values that survive four bytes
                // exactly. Fixture data straight from arbitrary Doubles would not, and the
                // round trip would be testing the fixture rather than the encoding.
                frame[seat] =
                    CarInput(
                        steer: Double((tick + index) % 20) / 10 - 1,
                        throttle: Double(tick % 3) - 1,
                        aim: tick % 4 == 0 ? nil : Double(tick % 628) / 100 - 3.14
                    ).quantised
            }
            inputs.append(frame)
        }
        return LapGhost(
            start: LapGhost.Start(
                tick: 180,
                cars: players.map {
                    LapGhost.CarPose(
                        seat: $0, position: Vec2(1, 2), velocity: Vec2(3, 4), heading: 0.5,
                        height: 0, steerActuator: 0.1)
                }),
            seed: 7, players: players, inputs: inputs, ticks: Tick(ticks))
    }

    /// **The round trip is exact**, because the sim only ever steps quantised values — so
    /// the four bytes are the numbers it used rather than an approximation of them.
    @Test func packingRoundTripsExactly() throws {
        for seats in [1, 2, 4] {
            let original = ghost(seats: seats, ticks: 120)
            let data = try JSONEncoder().encode(original)
            let back = try JSONDecoder().decode(LapGhost.self, from: data)
            #expect(back == original, "a \(seats)-seat ghost did not survive the round trip")
        }
    }

    /// **Four bytes a tick a seat**, which is the whole point.
    @Test func inputsCostFourBytesPerTickPerSeat() {
        let packed = LapGhost.pack(
            ghost(seats: 2, ticks: 100).inputs, players: [PlayerID(0), PlayerID(1)])
        #expect(packed.count == 100 * 2 * CarInputWire.byteCount)
    }

    /// A seat missing from a frame reads back as coast — what the sim does with it anyway,
    /// so the round trip is faithful to the race rather than to the dictionary.
    @Test func aMissingSeatBecomesCoast() {
        let players = [PlayerID(0), PlayerID(1)]
        let packed = LapGhost.pack([[PlayerID(0): CarInput(throttle: 1)]], players: players)
        let back = LapGhost.unpack(packed, players: players)
        #expect(back.count == 1)
        #expect(back[0][PlayerID(1)] == CarInput.coast)
    }

    /// **A truncated file costs the last tick, not a half-decoded one.** A frame with two
    /// of its three channels set would be a car steering into a wall for reasons nobody
    /// could explain.
    @Test func aTruncatedFrameIsDropped() {
        let players = [PlayerID(0)]
        var packed = LapGhost.pack(
            [[PlayerID(0): CarInput(throttle: 1)], [PlayerID(0): CarInput(steer: 1)]],
            players: players)
        packed.removeLast(2)  // half of the second frame
        #expect(LapGhost.unpack(packed, players: players).count == 1)
    }

    /// Empty in, empty out — no crash on a ghost with no inputs.
    @Test func anEmptyGhostPacksToNothing() {
        #expect(LapGhost.pack([], players: [PlayerID(0)]).isEmpty)
        #expect(LapGhost.unpack(Data(), players: [PlayerID(0)]).isEmpty)
        #expect(LapGhost.unpack(Data([1, 2, 3, 4]), players: []).isEmpty)
    }
}
