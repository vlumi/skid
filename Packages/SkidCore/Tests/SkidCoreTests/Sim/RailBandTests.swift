import XCTest

@testable import SkidCore

/// **A rail's outboard band belongs beside the rail, not off its end.**
///
/// A rail is a line in the model but a BAND on screen: the kerb is painted
/// `kerbBand` outboard of the nominal road edge, and because an elevated road is
/// drawn wider, that gap reaches 27 units at deck height. `outboardThickness`
/// adds it to the collision reach so a car stops against the painted face rather
/// than in mid-air.
///
/// Off the END of a segment there is no face to stand off from, and granting the
/// band there is pure invention. It produced the worst warp yet found: measured on
/// a user-built track, a car 39.8 units clear of a 6-unit rail's endpoint counted
/// as contact (reach had grown to 39), and because it sat behind the face the
/// overlap came out `39 − (−3.4)` — a **42-unit shove** off the road, through a
/// continuous railing, into a fall. Reported as "found a spot where the car gets
/// through, and of course can't get back on the track".
final class RailBandTests: XCTestCase {
    /// The reported track, reduced to its essentials: a deck rail as a short
    /// segment, with the car off its end rather than beside it.
    private func track() -> Track {
        Track(
            centerline: [Vec2(-4000, 0), Vec2(4000, 0)], width: 96,
            startSlots: [Vec2(0, 0)], size: Vec2(9000, 4000))
    }

    /// **A car off the end of a rail is not pushed.** The whole warp in one test:
    /// the car sits 40 units past a short deck rail's endpoint, which is inside the
    /// inflated reach but beside nothing.
    func testACarOffTheEndOfARailIsNotShoved() {
        var race = Race(track: track(), players: [PlayerID(0)], config: RaceConfig(laps: nil))
        // A 6-unit rail at deck height, as a ramp's curve produces.
        let rail = Wall(
            from: Vec2(0, 0), to: Vec2(0, 6), height: 1, kind: .rail,
            outward: Vec2(-1, 0), onClimb: true)
        // The car is off the rail's END, 40 units away — far outside any real
        // contact, but within the 39-unit reach the band used to grant.
        let from = Vec2(-10, -38)
        var car = race.cars[0].state
        car.position = from + Vec2(1, 1)
        car.height = 1
        car.velocity = Vec2(60, 60)
        let before = car.position
        _ = race.collideWithWalls(car: &car, movedFrom: from, walls: [rail])
        XCTAssertEqual(
            (car.position - before).length, 0, accuracy: 1,
            "a car off the end of a rail must not be displaced at all")
    }

    /// And beside the rail the band still works: a car approaching from outboard
    /// stops clear of the painted face, not at the bare collision line.
    func testTheBandStillStopsACarBesideTheRail() {
        var race = Race(track: track(), players: [PlayerID(0)], config: RaceConfig(laps: nil))
        let rail = Wall(
            from: Vec2(0, -200), to: Vec2(0, 200), height: 1, kind: .rail,
            outward: Vec2(-1, 0), onClimb: false)
        var car = race.cars[0].state
        car.position = Vec2(-14, 0)  // outboard, inside the band
        car.height = 1
        car.velocity = Vec2(200, 0)  // driving into the rail
        _ = race.collideWithWalls(car: &car, movedFrom: Vec2(-30, 0), walls: [rail])
        XCTAssertLessThan(
            car.position.x, -14 + 0.001,
            "an outboard car must be pushed away from the rail, never through it")
        XCTAssertGreaterThan(
            abs(car.position.x), CarGeometry.radius,
            "and must end up clear of the collision line")
    }

    /// **No wall may ever move a car further than it was from that wall.** The
    /// invariant the warp violated: a correction closes a gap, it cannot open one.
    func testNoPushExceedsTheSeparation() {
        var race = Race(track: track(), players: [PlayerID(0)], config: RaceConfig(laps: nil))
        let rail = Wall(
            from: Vec2(0, 0), to: Vec2(0, 6), height: 1, kind: .rail,
            outward: Vec2(-1, 0), onClimb: true)
        for dx in [-40.0, -30, -20, -13, -6] {
            for dy in [-40.0, -20, 0, 20, 40] {
                var car = race.cars[0].state
                car.position = Vec2(dx, dy)
                car.height = 1
                car.velocity = Vec2(100, 0)
                let from = car.position - Vec2(2, 2)
                let closest = car.position.closestPoint(onSegment: rail.a, rail.b)
                let separation = (car.position - closest).length
                let before = car.position
                _ = race.collideWithWalls(car: &car, movedFrom: from, walls: [rail])
                XCTAssertLessThan(
                    (car.position - before).length, separation + 1,
                    "at (\(dx),\(dy)) the push must not exceed the \(Int(separation))u separation")
            }
        }
    }
}
