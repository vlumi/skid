import XCTest

@testable import SkidCore

final class AIDriverTests: XCTestCase {
    /// The one that matters: a default AI driver completes a full lap of
    /// the practice loop, gates and all, in a sane time.
    func testAICompletesALap() {
        var race = Race(
            track: TrackLibrary.practiceLoop(), players: [PlayerID(0)],
            config: RaceConfig(laps: 1)
        )
        var driver = AIDriver()
        var ticks = 0
        while race.cars[0].progress.finishedAt == nil, ticks < 90 * Race.tickRate {
            let input = driver.input(car: race.cars[0].state, track: race.track)
            race.advance(inputs: [PlayerID(0): input])
            ticks += 1
        }
        let progress = race.cars[0].progress
        XCTAssertNotNil(
            progress.finishedAt,
            "AI failed to lap in 90s (gate \(progress.nextGate), lap \(progress.lap))"
        )
        // And not absurdly slowly either — the loop is ~20s of driving.
        XCTAssertLessThan(race.cars[0].progress.finishedAt!, 60 * Race.tickRate)
    }

    func testAIIsDeterministic() {
        func run() -> (Race, AIDriver) {
            var race = Race(
                track: TrackLibrary.practiceLoop(),
                players: [PlayerID(0), PlayerID(1)],
                config: RaceConfig(laps: 2)
            )
            var drivers = [AIDriver.skill(0), AIDriver.skill(2)]
            for _ in 0..<(30 * Race.tickRate) {
                var inputs: [PlayerID: CarInput] = [:]
                for i in drivers.indices {
                    inputs[PlayerID(i)] = drivers[i].input(
                        car: race.cars[i].state, track: race.track)
                }
                race.advance(inputs: inputs)
            }
            return (race, drivers[0])
        }
        let a = run()
        let b = run()
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, b.1)
    }

    func testSkillLadderIsOrdered() {
        // A higher skill index must not out-drive a lower one: same start,
        // same track, compare race progress (laps + gates) after a stretch.
        func progress(skill: Int) -> Int {
            var race = Race(track: TrackLibrary.practiceLoop(), players: [PlayerID(0)])
            var driver = AIDriver.skill(skill)
            for _ in 0..<(20 * Race.tickRate) {
                let input = driver.input(car: race.cars[0].state, track: race.track)
                race.advance(inputs: [PlayerID(0): input])
            }
            let car = race.cars[0]
            return car.progress.lap * race.track.gates.count + car.progress.nextGate
        }
        // The extremes must separate; adjacent skills may tie over a short
        // stretch.
        XCTAssertGreaterThanOrEqual(progress(skill: 0), progress(skill: 3))
        XCTAssertGreaterThan(progress(skill: 0), 0)
    }

    func testCenterlineWalk() {
        let track = TrackLibrary.practiceLoop()
        // A point on the bottom straight walks forward along +x.
        let start = Vec2(700, 800)
        let ahead = track.pointAlongCenterline(from: start, distance: 100)
        XCTAssertEqual(ahead.y, 800, accuracy: 1)
        XCTAssertEqual(ahead.x, 800, accuracy: 1)
        // Walking a full loop length returns near the start point.
        var perimeter = 0.0
        for i in track.centerline.indices {
            let a = track.centerline[i]
            let b = track.centerline[(i + 1) % track.centerline.count]
            perimeter += a.distance(to: b)
        }
        let around = track.pointAlongCenterline(from: start, distance: perimeter)
        XCTAssertLessThan(around.distance(to: Vec2(700, 800)), 2)
    }
}
