import XCTest

@testable import SkidCore

/// **A wall must not put a car on its far side.** Two ways that happened, both
/// reported from a real track (the flat eight): the car ended up outside the map
/// fence and stuck there.
///
/// 1. The push-out used the direction from the wall to where the car *ended up*.
///    Once the step carried it past the wall that direction points the wrong way,
///    so the correction shoved it further out — a 30-unit step across the fence at
///    x = 8 landed the car at x = −4.
/// 2. A longer step misses entirely: the nearest-approach test samples only the
///    start, middle and end of the movement, so nothing within reach of the wall
///    means no collision at all, whatever the path crossed.
final class WallTunnellingTests: XCTestCase {
    /// The reported track.
    private func track() throws -> Track {
        try PieceCompiler.compile(
            TrackCode.decode("AbcBDh8KDBEFeQUFFXoGBHgEAgIADAMFAtAA8AA"))
    }

    private func race(_ track: Track) -> Race {
        Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
    }

    /// A car crossing the map fence must be left INSIDE it, at any speed. Top
    /// speed is 520 units/s, so a tick covers ~8.7 — but a bounce or a launch can
    /// carry further, and the fence is the last line before the void.
    func testTheMapFenceKeepsACarInsideAtEverySpeed() throws {
        let track = try track()
        var race = race(track)
        // Straight at the left fence (x = 8) from inside.
        for step in [10.0, 30.0, 60.0, 120.0, 300.0] {
            var car = race.cars[0].state
            car.height = 0
            let from = Vec2(28, 600)
            car.position = Vec2(28 - step, 600)
            car.velocity = Vec2(-step * Double(Race.tickRate), 0)
            _ = race.collideWithWalls(car: &car, movedFrom: from)
            XCTAssertGreaterThan(
                car.position.x, 8,
                "a \(step)-unit step put the car outside the fence at x=\(car.position.x)")
        }
    }

    /// The same for the other three sides, so the fix isn't one-sided.
    func testEveryFenceSideHolds() throws {
        let track = try track()
        var race = race(track)
        let mid = Vec2(track.size.x / 2, track.size.y / 2)
        struct Probe {
            var name: String
            var inside: Vec2
            var out: Vec2
        }
        let probes: [Probe] = [
            Probe(name: "left", inside: Vec2(28, mid.y), out: Vec2(-100, mid.y)),
            Probe(
                name: "right", inside: Vec2(track.size.x - 28, mid.y),
                out: Vec2(track.size.x + 100, mid.y)),
            Probe(name: "top", inside: Vec2(mid.x, 28), out: Vec2(mid.x, -100)),
            Probe(
                name: "bottom", inside: Vec2(mid.x, track.size.y - 28),
                out: Vec2(mid.x, track.size.y + 100)),
        ]
        for probe in probes {
            var car = race.cars[0].state
            car.height = 0
            car.position = probe.out
            car.velocity = (probe.out - probe.inside).normalized * 520
            _ = race.collideWithWalls(car: &car, movedFrom: probe.inside)
            XCTAssertTrue(
                car.position.x > 8 && car.position.x < track.size.x - 8
                    && car.position.y > 8 && car.position.y < track.size.y - 8,
                "\(probe.name): car escaped to \(car.position)")
        }
    }

    /// A car that legitimately drives up to a wall is still stopped short of it,
    /// not teleported — the fix must not turn contact into a shove.
    func testApproachingAWallStillStopsShortOfIt() throws {
        let track = try track()
        var race = race(track)
        var car = race.cars[0].state
        car.height = 0
        let from = Vec2(40, 600)
        car.position = Vec2(18, 600)  // 10 units from the fence, inside
        car.velocity = Vec2(-100, 0)
        _ = race.collideWithWalls(car: &car, movedFrom: from)
        XCTAssertGreaterThanOrEqual(car.position.x, 8 + CarGeometry.radius - 0.001)
        XCTAssertLessThan(car.position.x, 40, "the car should be held near the wall")
    }

    /// Rails guarding a deck must not fling a car off the bridge either.
    func testADeckRailKeepsACarOnTheRoadSide() throws {
        let track = try track()
        var race = race(track)
        guard
            let rail = track.walls.first(where: {
                $0.kind == .rail && $0.height > 0.9 && $0.outward.length > 0.001
            })
        else { throw XCTSkip("no deck rail on this track") }
        var car = race.cars[0].state
        car.height = rail.height
        let mid = (rail.a + rail.b) * 0.5
        // Start on the road side, end well past the rail on the outboard side.
        let from = mid - rail.outward * 25
        car.position = mid + rail.outward * 60
        car.velocity = rail.outward * 400
        _ = race.collideWithWalls(car: &car, movedFrom: from)
        let side = (car.position - mid).dot(rail.outward)
        XCTAssertLessThan(side, 25, "the car was left outboard of the rail it crossed")
    }
}
