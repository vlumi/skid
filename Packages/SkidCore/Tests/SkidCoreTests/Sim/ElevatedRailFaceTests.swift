import XCTest

@testable import SkidCore

/// **The wall the car meets is the wall the player sees.** Rails are compiled at
/// the road's NOMINAL edge, but an elevated road draws wider — on the inboard
/// side the visible railing stands the widening past the collision segment.
/// Stopping at the segment slammed cars into an invisible wall in the middle of
/// visible asphalt; reported on a rising curve's inner rail as a weird bounce
/// straight back (with the flung tire marks to prove it).
final class ElevatedRailFaceTests: XCTestCase {
    /// A deck-height straight along y, its rail at the nominal edge x = 60,
    /// outward +x — the compiled shape of an inner rail seen from the road.
    private func fixture() -> (race: Race, rail: Wall) {
        let track = Track(
            centerline: [Vec2(0, -400), Vec2(0, 400)],
            width: 120, heights: [1, 1], size: Vec2(2_000, 2_000))
        let race = Race(
            track: track, players: [PlayerID(0)],
            config: RaceConfig(laps: 3, countdownTicks: 0))
        let rail = Wall(
            from: Vec2(60, -400), to: Vec2(60, 400), height: 1, kind: .rail,
            outward: Vec2(1, 0))
        return (race, rail)
    }

    /// Driving near the widened edge — where the OLD face (the nominal segment)
    /// already counted the car as touching, but the drawn railing is still a
    /// car-radius away — is not a collision.
    func testTheWidenedStripIsDrivable() {
        let (race, rail) = fixture()
        let painted = race.track.halfWidth(atHeight: 1)
        XCTAssertGreaterThan(painted - 60, 8, "the fixture needs real widening to test")
        // Center at 55: within radius of the segment at 60 (old contact), but
        // 17 clear of the drawn face at 72 (no real contact).
        var car = CarState(
            position: Vec2(55, 0), velocity: Vec2(120, 0), height: 1)
        let impact = race.collideWithWalls(
            car: &car, movedFrom: Vec2(50, 0), walls: [rail])
        XCTAssertEqual(impact, 0, "an invisible wall stood in the middle of the road")
        XCTAssertEqual(car.position.x, 55, accuracy: 1e-9, "the car was shoved back")
        XCTAssertEqual(car.velocity.x, 120, accuracy: 1e-9)
    }

    /// The drawn railing still stops the car — at ITS face, not never.
    func testTheDrawnRailingStillStops() {
        let (race, rail) = fixture()
        let painted = race.track.halfWidth(atHeight: 1)
        var car = CarState(
            position: Vec2(painted - 2, 0), velocity: Vec2(120, 0), height: 1)
        let impact = race.collideWithWalls(
            car: &car, movedFrom: Vec2(painted - 14, 0), walls: [rail])
        XCTAssertGreaterThan(impact, 0, "the railing has stopped existing")
        XCTAssertLessThanOrEqual(
            car.position.x, painted - CarGeometry.radius + 1e-9,
            "the car ended inside the drawn railing")
    }

    /// **No warp-through at a curved wall's seams.** The first fix shifted the
    /// FACE per approach instead of the segment: a car legitimately sitting
    /// past the stored line had its side test flip at the joint between two
    /// rail segments, and the next segment ejected it through the railing
    /// (reported from device, with the car ending on the grass outside). With
    /// the whole segment translated, the car is never past the wall — sweep a
    /// car hard into the joint of an outer curve and it must stay inside.
    func testNoEscapeAtACurvedWallSeam() {
        let track = Track(
            centerline: [Vec2(0, -400), Vec2(0, 400)],
            width: 120, heights: [3, 3], size: Vec2(4_000, 4_000))
        let race = Race(
            track: track, players: [PlayerID(0)],
            config: RaceConfig(laps: 3, countdownTicks: 0))
        // Two rail segments meeting at a 22.5-degree joint, outward away from
        // the road — an outer curve's corner, where the translated spans open
        // a small wedge.
        let joint = Vec2(120, 0)
        let turn = 22.5 * Double.pi / 180
        let rails = [
            Wall(
                from: joint - Vec2(0, 1) * 200, to: joint, height: 3, kind: .rail,
                outward: Vec2(1, 0)),
            Wall(
                from: joint, to: joint + Vec2(sin(turn), cos(turn)) * 200,
                height: 3, kind: .rail, outward: Vec2(cos(turn), -sin(turn))),
        ]
        let widening = track.halfWidth(atHeight: 3) - track.width / 2
        // Drive straight at the joint's corner wedge from inside, fast enough
        // to cross the whole widening in one tick.
        var car = CarState(
            position: Vec2(joint.x + widening + 30, 2), velocity: Vec2(600, 0),
            height: 3)
        let impact = race.collideWithWalls(
            car: &car, movedFrom: Vec2(joint.x - 40, 2), walls: rails)
        XCTAssertGreaterThan(impact, 0, "the seam let the car through")
        XCTAssertLessThanOrEqual(
            car.position.x, joint.x + widening + CarGeometry.radius,
            "the car ended outside the railing")
    }

    /// At ground height there is no widening, so the face IS the segment —
    /// flat-track collisions are bit-identical to before.
    func testGroundRailsAreUntouched() {
        let track = Track(
            centerline: [Vec2(0, -400), Vec2(0, 400)],
            width: 120, size: Vec2(2_000, 2_000))
        let race = Race(
            track: track, players: [PlayerID(0)],
            config: RaceConfig(laps: 3, countdownTicks: 0))
        let rail = Wall(
            from: Vec2(60, -400), to: Vec2(60, 400), height: 0, kind: .rail,
            outward: Vec2(1, 0))
        var car = CarState(position: Vec2(55, 0), velocity: Vec2(120, 0))
        let impact = race.collideWithWalls(
            car: &car, movedFrom: Vec2(40, 0), walls: [rail])
        XCTAssertGreaterThan(impact, 0)
        XCTAssertEqual(car.position.x, 60 - CarGeometry.radius, accuracy: 1e-6)
    }
}
