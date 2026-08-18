import XCTest

@testable import SkidCore

/// **A rail's outboard reach is the kerb band, nothing more.** The collision
/// segment sits at the DRAWN road edge (see `PieceCompilerWalls.deckRails`), so
/// the only structure beyond it is the painted band's outer half — `kerbBand`.
/// `railThickness` still added the elevation widening on top, double-counting
/// what the segment already includes: an elevated rail reached up to a road
/// width's widening PAST its drawn band. On a spiral track whose lower pass
/// runs just outside an upper pass's inner rail, that phantom reach bit cars on
/// their own road wherever the two passes' heights converge — which is on the
/// climbs. Reported as a weird bounce off a rising curve's inner wall.
final class RailReachTests: XCTestCase {
    private struct Fixture {
        var race: Race
        var rail: Wall
        var edge: Double
    }

    private func fixture(height: Double) -> Fixture {
        let track = Track(
            centerline: [Vec2(0, -400), Vec2(0, 400)],
            width: 120, heights: [height, height], size: Vec2(2_000, 2_000))
        let race = Race(
            track: track, players: [PlayerID(0)],
            config: RaceConfig(laps: 3, countdownTicks: 0))
        // The compiled shape: the rail AT the drawn edge, outward away from
        // the road.
        let edge = track.halfWidth(atHeight: height)
        let rail = Wall(
            from: Vec2(edge, -400), to: Vec2(edge, 400), height: height,
            kind: .rail, outward: Vec2(1, 0))
        return Fixture(race: race, rail: rail, edge: edge)
    }

    /// From outside, the car stops against the painted band — kerb width past
    /// the drawn edge — not a widening further out.
    func testOutsideContactStopsAtThePaintedBand() {
        let f = fixture(height: 3)
        let face = f.edge + Double(PieceCatalog.kerbBand)
        var car = CarState(
            position: Vec2(face + 5, 0), velocity: Vec2(-200, 0), height: 3)
        _ = f.race.collideWithWalls(
            car: &car, movedFrom: Vec2(face + 30, 0), walls: [f.rail])
        XCTAssertGreaterThanOrEqual(
            car.position.x, face + CarGeometry.radius - 1e-6,
            "the car passed the painted band")
        XCTAssertLessThanOrEqual(
            car.position.x, face + CarGeometry.radius + 6,
            "the car was held far outside the painted band — the phantom reach")
    }

    /// **No phantom wall in the clear.** A car at gate-matching height, well
    /// outside the painted band but inside the OLD widening-inflated reach,
    /// must be untouched — this is the lower pass of a spiral brushing the
    /// upper pass's invisible overhang.
    func testNoPhantomReachBeyondTheBand() {
        let f = fixture(height: 3)
        let start = Vec2(f.edge + Double(PieceCatalog.kerbBand) + CarGeometry.radius + 8, 0)
        var car = CarState(position: start, velocity: Vec2(0, 250), height: 3)
        let impact = f.race.collideWithWalls(
            car: &car, movedFrom: start - Vec2(0, 4), walls: [f.rail])
        XCTAssertEqual(impact, 0, "an invisible wall bit outside the painted band")
        XCTAssertEqual(car.position.x, start.x, accuracy: 1e-9)
        XCTAssertEqual(car.velocity.y, 250, accuracy: 1e-9)
    }

    /// Ground rails are unchanged: the widening is zero there, so the reach was
    /// always just the kerb band.
    func testGroundReachIsUnchanged() {
        let f = fixture(height: 0)
        XCTAssertEqual(f.edge, 60, accuracy: 1e-9)
        let face = f.edge + Double(PieceCatalog.kerbBand)
        var car = CarState(position: Vec2(face + 4, 0), velocity: Vec2(-200, 0))
        _ = f.race.collideWithWalls(
            car: &car, movedFrom: Vec2(face + 30, 0), walls: [f.rail])
        XCTAssertEqual(
            car.position.x, face + CarGeometry.radius, accuracy: 1e-6)
    }
}
