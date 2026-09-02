import XCTest

@testable import SkidCore

final class RaceEventTests: XCTestCase {
    func testWallImpactEmitsOnce() {
        var track = Track(
            centerline: [Vec2(-10000, 0), Vec2(10000, 0)],
            width: 600,
            startSlots: [Vec2.zero],
            size: Vec2(20000, 4000)
        )
        track.walls = [Wall(from: Vec2(400, -500), to: Vec2(400, 500))]
        var race = Race(track: track, players: [PlayerID(0)])
        var impacts = 0
        for _ in 0..<(4 * Race.tickRate) {
            race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
            for case .wallImpact(let id, let speed) in race.lastEvents {
                XCTAssertEqual(id, PlayerID(0))
                XCTAssertGreaterThan(speed, 60)
                impacts += 1
            }
        }
        XCTAssertGreaterThanOrEqual(impacts, 1)
        XCTAssertLessThanOrEqual(impacts, 3, "a single crash shouldn't machine-gun events")
    }

    func testCarImpactEmitsInContactMode() {
        let track = Track(
            centerline: [Vec2(-10000, 0), Vec2(10000, 0)],
            width: 800,
            startSlots: [Vec2(-140, 0), Vec2(140, 0)],
            size: Vec2(20000, 4000)
        )
        var race = Race(
            track: track, players: [PlayerID(0), PlayerID(1)],
            config: RaceConfig())
        // Pin the grid so the two cars face each other head-on regardless of
        // the random start-slot shuffle: car 0 left, car 1 right facing back.
        race.cars[0].state.position = Vec2(-140, 0)
        race.cars[1].state.position = Vec2(140, 0)
        race.cars[1].state.heading = .pi
        var sawImpact = false
        for _ in 0..<(4 * Race.tickRate) {
            race.advance(inputs: [
                PlayerID(0): CarInput(throttle: 1),
                PlayerID(1): CarInput(throttle: 1),
            ])
            for case .carImpact(let a, let b, let closing) in race.lastEvents {
                XCTAssertEqual(Set([a, b]), Set([PlayerID(0), PlayerID(1)]))
                XCTAssertGreaterThan(closing, 70)
                sawImpact = true
            }
        }
        XCTAssertTrue(sawImpact)
    }

    /// **The best lap is the fastest one driven so far, and absent before any
    /// lap exists** — the results card stars the race's fastest lap and the
    /// HUD highlights a personal best off exactly this reading. The second lap
    /// is made slower by driving back past the gate and returning; every loop
    /// is BOUNDED, because a `while` on sim state hung the suite once.
    func testBestLapTracksTheFastestDrivenLap() {
        let track = Track(
            centerline: [Vec2(-20000, 0), Vec2(20000, 0)],
            width: 600,
            gates: [Gate(from: Vec2(400, -300), to: Vec2(400, 300), forward: Vec2(1, 0))],
            startSlots: [Vec2.zero],
            size: Vec2(40000, 4000)
        )
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: 3))
        XCTAssertNil(race.cars[0].progress.bestLapTicks, "a best lap before any lap")
        func drive(throttle: Double, seconds: Double, orLap lap: Int? = nil) {
            for _ in 0..<Int(seconds * Double(Race.tickRate)) {
                if let lap, race.cars[0].progress.lap >= lap { return }
                race.advance(inputs: [PlayerID(0): CarInput(throttle: throttle)])
            }
        }
        drive(throttle: 1, seconds: 10, orLap: 1)
        guard race.cars[0].progress.lap == 1 else { return XCTFail("lap 1 never happened") }
        let firstLap = race.cars[0].progress.lapTimes[0]
        XCTAssertEqual(race.cars[0].progress.bestLapTicks, firstLap)
        // Back behind the gate (a backward crossing must not count), then
        // forward across it again — a second, far slower lap.
        drive(throttle: -1, seconds: 8)
        drive(throttle: 1, seconds: 30, orLap: 2)
        guard race.cars[0].progress.lap == 2 else { return XCTFail("lap 2 never happened") }
        XCTAssertGreaterThan(race.cars[0].progress.lapTimes[1], firstLap, "fixture: laps equal")
        XCTAssertEqual(
            race.cars[0].progress.bestLapTicks, firstLap,
            "a slower second lap must not steal the best")
    }

    /// **Intermediate gates announce themselves; the finish line does not
    /// double-speak.** Three gates and one lap: the two mid-course gates emit
    /// `gateCrossed`, the wrap emits `lapCompleted` (and here `finished`) with
    /// NO `gateCrossed` alongside — one crossing, one event.
    func testIntermediateGatesEmitGateCrossed() {
        func gate(x: Double) -> Gate {
            Gate(from: Vec2(x, -300), to: Vec2(x, 300), forward: Vec2(1, 0))
        }
        let track = Track(
            centerline: [Vec2(-20000, 0), Vec2(20000, 0)],
            width: 600,
            gates: [gate(x: 400), gate(x: 900), gate(x: 1400)],
            startSlots: [Vec2.zero],
            size: Vec2(40000, 4000)
        )
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
        var gates = 0
        var lapTickEvents: [RaceEvent] = []
        for _ in 0..<(10 * Race.tickRate) {
            race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
            for case .gateCrossed(let id) in race.lastEvents {
                XCTAssertEqual(id, PlayerID(0))
                gates += 1
            }
            if race.lastEvents.contains(where: {
                if case .lapCompleted = $0 { return true } else { return false }
            }) {
                lapTickEvents = race.lastEvents
            }
        }
        XCTAssertEqual(gates, 2, "two intermediate gates, two events")
        XCTAssertFalse(
            lapTickEvents.contains {
                if case .gateCrossed = $0 { return true } else { return false }
            },
            "the finish line spoke twice: \(lapTickEvents)")
    }

    func testLapAndFinishEventsMatchProgress() {
        func gate(x: Double) -> Gate {
            Gate(from: Vec2(x, -300), to: Vec2(x, 300), forward: Vec2(1, 0))
        }
        let track = Track(
            centerline: [Vec2(-20000, 0), Vec2(20000, 0)],
            width: 600,
            gates: [gate(x: 400), gate(x: 900), gate(x: 1400)],
            startSlots: [Vec2.zero],
            size: Vec2(40000, 4000)
        )
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
        var laps = 0
        var finishes = 0
        for _ in 0..<(10 * Race.tickRate) {
            race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
            for event in race.lastEvents {
                switch event {
                case .lapCompleted(let id, let lapTicks):
                    XCTAssertEqual(id, PlayerID(0))
                    XCTAssertEqual(lapTicks, race.cars[0].progress.lapTimes.last)
                    laps += 1
                case .finished(let id):
                    XCTAssertEqual(id, PlayerID(0))
                    finishes += 1
                default:
                    break
                }
            }
        }
        XCTAssertEqual(laps, 1)
        XCTAssertEqual(finishes, 1)
    }
}
