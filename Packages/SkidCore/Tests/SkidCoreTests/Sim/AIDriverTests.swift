import XCTest

@testable import SkidCore

final class AIDriverTests: XCTestCase {
    /// The one that matters: a default AI driver completes a full lap of
    /// the practice loop, gates and all, in a sane time.
    func testAICompletesALap() {
        var race = Race(
            track: TrackLibrary.testRing(), players: [PlayerID(0)],
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

    /// **The hard driver laps every built-in under STOCK physics.** The test
    /// ring is gentle and used to be the only lap check, so a physics change
    /// the AI cannot drive would have shipped silently. Now it fails HERE,
    /// not on a device.
    func testHardAILapsEveryBuiltin() {
        for builtin in TrackLibrary.builtins {
            let track = TrackLibrary.track(id: builtin.id)
            var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
            var driver = AIDriver.make(.hard, gridIndex: 0)
            var ticks = 0
            while race.cars[0].progress.finishedAt == nil, ticks < 120 * Race.tickRate {
                let input = driver.input(car: race.cars[0].state, track: race.track)
                race.advance(inputs: [PlayerID(0): input])
                ticks += 1
            }
            XCTAssertNotNil(
                race.cars[0].progress.finishedAt,
                "hard AI failed to lap '\(builtin.id)' in 120 s under stock physics")
        }
    }

    /// **A full grid laps "eight" under stock physics.** Line-wander sends a
    /// medium driver wide BY DESIGN, and with speed-faded grip the recovery
    /// is the part that has to keep working. Cars collide, too. (Written
    /// chasing a "beached AI" report that turned out to be three FINISHERS
    /// parked past the flag — kept, because the fear it checks is real.)
    func testAMediumGridLapsEightTogether() {
        let track = TrackLibrary.track(id: "eight")
        let players = (0..<4).map { PlayerID($0) }
        var race = Race(track: track, players: players, config: RaceConfig(laps: 1))
        var drivers = players.indices.map { AIDriver.make(.medium, gridIndex: $0) }
        var ticks = 0
        func allFinished() -> Bool {
            race.cars.allSatisfy { $0.progress.finishedAt != nil }
        }
        while !allFinished(), ticks < 180 * Race.tickRate {
            var inputs: [PlayerID: CarInput] = [:]
            for (index, player) in players.enumerated() {
                inputs[player] = drivers[index].input(
                    car: race.cars[index].state, track: race.track)
            }
            race.advance(inputs: inputs)
            ticks += 1
        }
        for car in race.cars {
            XCTAssertNotNil(
                car.progress.finishedAt,
                "car \(car.id) never lapped eight (gate \(car.progress.nextGate))")
        }
    }

    /// **Three medium AI lap around a PARKED car, three times.** The
    /// autostarted-simulator scene: an idle human car sits on the grid all
    /// race and the AI must dodge it at speed every lap — a collision at pace
    /// with speed-faded grip is a recovery case a clean grid never hits.
    func testAIsLapEightAroundAParkedCar() {
        let track = TrackLibrary.track(id: "eight")
        let players = (0..<4).map { PlayerID($0) }
        var race = Race(track: track, players: players, config: RaceConfig(laps: 3))
        var drivers = [
            AIDriver.make(.medium, gridIndex: 0),
            AIDriver.make(.medium, gridIndex: 1),
            AIDriver.make(.medium, gridIndex: 2),
        ]
        var ticks = 0
        func aisFinished() -> Bool {
            race.cars.dropFirst().allSatisfy { $0.progress.finishedAt != nil }
        }
        while !aisFinished(), ticks < 300 * Race.tickRate {
            var inputs: [PlayerID: CarInput] = [PlayerID(0): .coast]
            for index in 0..<3 {
                inputs[PlayerID(index + 1)] = drivers[index].input(
                    car: race.cars[index + 1].state, track: race.track)
            }
            race.advance(inputs: inputs)
            ticks += 1
        }
        for car in race.cars.dropFirst() {
            XCTAssertNotNil(
                car.progress.finishedAt,
                "car \(car.id) beached at gate \(car.progress.nextGate), lap \(car.progress.lap)"
            )
        }
    }

    func testAIIsDeterministic() {
        func run() -> (Race, AIDriver) {
            var race = Race(
                track: TrackLibrary.testRing(),
                players: [PlayerID(0), PlayerID(1)],
                config: RaceConfig(laps: 2)
            )
            var drivers = [AIDriver.make(.hard), AIDriver.make(.easy, gridIndex: 2)]
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

    func testDifficultiesAreOrderedAndEasyStillLaps() {
        // Same start, same track, free running (no finish to park at):
        // harder drivers make more progress.
        func progress(_ driver: AIDriver, seconds: Int, laps: Int? = nil) -> (
            score: Int, race: Race
        ) {
            var race = Race(
                track: TrackLibrary.testRing(), players: [PlayerID(0)],
                config: RaceConfig(laps: laps))
            var ai = driver
            for _ in 0..<(seconds * Race.tickRate) {
                let input = ai.input(car: race.cars[0].state, track: race.track)
                race.advance(inputs: [PlayerID(0): input])
            }
            let car = race.cars[0]
            return (car.progress.lap * race.track.gates.count + car.progress.nextGate, race)
        }
        let easy = progress(AIDriver.make(.easy), seconds: 40)
        let medium = progress(AIDriver.make(.medium), seconds: 40)
        let hard = progress(AIDriver.make(.hard), seconds: 40)
        XCTAssertGreaterThanOrEqual(hard.score, medium.score)
        XCTAssertGreaterThanOrEqual(medium.score, easy.score)
        XCTAssertGreaterThan(hard.score, easy.score)
        // And even the wobbliest easy driver finishes a lap eventually.
        let longEasy = progress(AIDriver.make(.easy, gridIndex: 2), seconds: 90, laps: 1)
        XCTAssertNotNil(longEasy.race.cars[0].progress.finishedAt)
    }

    func testEasyDriverActuallyTouchesGrass() {
        // Device feedback: Easy looked too clean. Its line wander must be
        // big enough to genuinely run wide off the ribbon now and then.
        var race = Race(track: TrackLibrary.testRing(), players: [PlayerID(0)])
        var driver = AIDriver.make(.easy)
        var grassTicks = 0
        for _ in 0..<(45 * Race.tickRate) {
            let input = driver.input(car: race.cars[0].state, track: race.track)
            race.advance(inputs: [PlayerID(0): input])
            if race.track.surface(at: race.cars[0].state.position) == .grass {
                grassTicks += 1
            }
        }
        XCTAssertGreaterThan(grassTicks, 30, "easy AI never ran wide onto the grass")
    }

    func testCenterlineWalkEdgeCases() {
        let track = TrackLibrary.testRing()
        // Distances beyond a full loop wrap instead of bailing out.
        let start = Vec2(700, 800)
        let wrapped = track.pointAlongCenterline(
            from: start, distance: track.centerlineLength * 10 + 100)
        let direct = track.pointAlongCenterline(from: start, distance: 100)
        XCTAssertLessThan(wrapped.distance(to: direct), 1e-6)
        // A degenerate loop with no length returns its first point.
        let dot = Track(centerline: [Vec2(5, 5), Vec2(5, 5)], width: 10, size: Vec2(10, 10))
        XCTAssertEqual(dot.pointAlongCenterline(from: .zero, distance: 50), Vec2(5, 5))
        // An empty centerline returns the query point.
        let empty = Track(centerline: [], width: 10, size: Vec2(10, 10))
        XCTAssertEqual(empty.pointAlongCenterline(from: Vec2(1, 2), distance: 50), Vec2(1, 2))
    }

    func testCenterlineWalk() throws {
        let track = TrackLibrary.testRing()
        // Walk from a point ON the centerline, so the result is comparable
        // without depending on any particular track shape.
        let start = try XCTUnwrap(track.centerline.first)
        let ahead = track.pointAlongCenterline(from: start, distance: 100)
        XCTAssertEqual(start.distance(to: ahead), 100, accuracy: 2, "walks the requested distance")
        // Walking a full loop length returns near the start point.
        var perimeter = 0.0
        for i in track.centerline.indices {
            let a = track.centerline[i]
            let b = track.centerline[(i + 1) % track.centerline.count]
            perimeter += a.distance(to: b)
        }
        let around = track.pointAlongCenterline(from: start, distance: perimeter)
        XCTAssertLessThan(around.distance(to: start), 2)
    }
}
