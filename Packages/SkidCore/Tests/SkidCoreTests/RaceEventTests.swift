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
            config: RaceConfig(carContact: true))
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
