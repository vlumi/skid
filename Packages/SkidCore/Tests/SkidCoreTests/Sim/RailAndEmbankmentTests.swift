import XCTest

@testable import SkidCore

/// **A railing and an embankment are two different walls**, and a ramp needs
/// both. Reported from device, from both directions:
///
/// - With rails reaching the floor, one bridge edge was solid in places and
///   see-through in others (24 of 32 near-deck rails fenced the ground, 8 did
///   not) because `trunc` split 0.999 from 1.0 into different storeys. That
///   also let a car be shoved *through* a railing where neighbors disagreed.
/// - Rounding them to their own level fixed that and removed the ramp's side
///   barrier — 64 of 136 walls stopped fencing the ground, so you could drive
///   under a ramp from the side.
///
/// Both are one wall doing two jobs. A **railing** is a waist-high barrier on
/// the road's edge, guarding its own level; it was never right to extend it to
/// the floor. An **embankment** is the earth under a climbing piece, from the
/// ground up to the road.
final class RailAndEmbankmentTests: XCTestCase {
    private func race() -> Race {
        Race(
            track: Track(
                centerline: [Vec2(-500, 0), Vec2(500, 0)], width: 200,
                startSlots: [.zero], size: Vec2(1000, 1000)),
            players: [PlayerID(0)])
    }

    private func car(atHeight height: Double) -> CarState {
        var car = CarState(position: .zero)
        car.height = height
        return car
    }

    private func wall(_ kind: Wall.Kind, _ height: Double) -> Wall {
        Wall(from: Vec2(0, 0), to: Vec2(100, 0), height: height, kind: kind)
    }

    // MARK: - Railings guard their own level, and nothing below

    /// A deck railing stops a deck car — including at 0.96, since an S-curve
    /// leaves the deck a hair under a whole level.
    func testARailingGuardsItsOwnLevel() {
        let race = race()
        for height in [0.96, 0.99, 1.0] {
            XCTAssertTrue(race.blocks(wall(.rail, height), car: car(atHeight: 1)))
        }
    }

    /// **And never reaches the floor.** The road below a bridge runs clear,
    /// whether the deck sits at 1.0 or a hair under.
    func testARailingDoesNotReachTheFloor() {
        let race = race()
        for height in [0.96, 0.99, 1.0] {
            XCTAssertFalse(
                race.blocks(wall(.rail, height), car: car(atHeight: 0)),
                "a railing at \(height) must not fence the ground beneath it")
        }
    }

    /// Every railing near deck height agrees about a ground car — no holes.
    func testTheBridgeRailingIsConsistent() {
        let track = TrackLibrary.track(id: "eight")
        let race = Race(track: track, players: [PlayerID(0)])
        let deck = track.walls.filter { $0.kind == .rail && $0.height > 0.9 }
        XCTAssertGreaterThan(deck.count, 8)
        XCTAssertEqual(
            Set(deck.map { race.blocks($0, car: car(atHeight: 0)) }), [false],
            "a fence with holes in it is the reported 'railing works erratically'")
    }

    /// **A rail mid-climb guards the car actually driving that stretch.**
    ///
    /// Rounding a rail's height to the nearest level promoted one at 0.52–0.75 to
    /// storey 1 and then demanded `height >= 0.8` — so it blocked nobody, and a
    /// drag along the barrier walked out through it. `onClimb` is why the wall can
    /// tell this from a sagging deck at the same height.
    func testAClimbRailGuardsItsOwnStretch() {
        let race = race()
        for height in [0.3, 0.52, 0.75, 0.98] {
            let rail = Wall(
                from: Vec2(0, 0), to: Vec2(100, 0), height: height, kind: .rail,
                outward: Vec2(0, 1), onClimb: true)
            XCTAssertTrue(
                race.blocks(rail, car: car(atHeight: height)),
                "a rail at \(height) on a climb must hold the car driving there")
        }
    }

    /// And the sagging-deck case keeps its old answer at the SAME heights: a flat
    /// rail belongs to its level, so the ground still passes underneath.
    func testASaggingDeckRailStillClearsTheGround() {
        let race = race()
        for height in [0.96, 0.99, 1.0] {
            let rail = Wall(
                from: Vec2(0, 0), to: Vec2(100, 0), height: height, kind: .rail,
                outward: Vec2(0, 1), onClimb: false)
            XCTAssertFalse(
                race.blocks(rail, car: car(atHeight: 0)),
                "a flat deck rail at \(height) must not fence the ground")
            XCTAssertTrue(race.blocks(rail, car: car(atHeight: 1)), "but holds the deck")
        }
    }

    /// The compiler records it, so real tracks get the distinction.
    func testTheCompilerMarksClimbingRails() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.bridgeRing), id: "t")
        let rails = track.walls.filter { $0.kind == .rail }
        XCTAssertFalse(rails.isEmpty)
        XCTAssertFalse(
            rails.filter(\.onClimb).isEmpty, "a bridge ring climbs, so some rails are on a climb")
        // And a mid-climb rail actually holds a car at its own height.
        let race = Race(track: track, players: [PlayerID(0)])
        for rail in rails.filter({ $0.onClimb && $0.height > 0.4 && $0.height < 0.9 }) {
            XCTAssertTrue(
                race.blocks(rail, car: car(atHeight: rail.height)),
                "mid-climb rail at \(rail.height) must hold a car on that stretch")
        }
    }

    // MARK: - Embankments are the earth under a climb

    /// An embankment fences the ground beside a ramp, whatever height the road
    /// above it has reached — that is what stops driving in from the flank.
    func testAnEmbankmentFencesTheGroundBesideARamp() {
        let race = race()
        for height in [0.2, 0.5, 0.96, 1.0] {
            XCTAssertTrue(
                race.blocks(wall(.embankment, height), car: car(atHeight: 0)),
                "earth under a road at \(height) must stop a ground car")
        }
    }

    /// But not a car above it — a deck crossing over a ramp is clear.
    func testAnEmbankmentDoesNotBlockAboveItsRoad() {
        let race = race()
        XCTAssertFalse(race.blocks(wall(.embankment, 0.4), car: car(atHeight: 1)))
    }

    // MARK: - Embankment flanks are ONE-WAY

    /// **You may drive OFF a ramp's flank, never INTO it.**
    ///
    /// The earth that stops a car below is the same segment a car above would
    /// leave over, so a symmetric flank traps you on a railless ramp. The side
    /// comes from the wall's stored `outward`, which points away from the road
    /// the earth carries — a question about the RAMP, not about one segment.
    func testAnEmbankmentBlocksFromOutsideOnly() {
        let race = race()
        // Earth under a road at 1.0, running +x, its bulk facing +y.
        let flank = Wall(
            from: Vec2(0, 0), to: Vec2(100, 0), height: 1, kind: .embankment,
            outward: Vec2(0, 1))
        XCTAssertTrue(
            race.blocks(flank, car: car(atHeight: 0), movedFrom: Vec2(50, 40)),
            "a ground car approaching the flank from outside must be stopped")
        XCTAssertFalse(
            race.blocks(flank, car: car(atHeight: 0), movedFrom: Vec2(50, -40)),
            "but leaving the ramp over its own edge must be allowed — that is the fall")
    }

    /// The side test holds along the whole segment and at any angle: `outward` is
    /// perpendicular to the wall, so travel ALONG it contributes nothing to the
    /// dot product and the endpoint anchor is enough.
    func testTheSideTestHoldsAlongTheWholeFlank() {
        let race = race()
        let diagonal = Vec2(1, -1).normalized
        let flank = Wall(
            from: Vec2(0, 0), to: Vec2(300, 300), height: 1, kind: .embankment,
            outward: diagonal)
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let on = Vec2(300 * fraction, 300 * fraction)
            XCTAssertTrue(
                race.blocks(flank, car: car(atHeight: 0), movedFrom: on + diagonal * 40),
                "outside at \(fraction) along the flank")
            XCTAssertFalse(
                race.blocks(flank, car: car(atHeight: 0), movedFrom: on - diagonal * 40),
                "inside at \(fraction) along the flank")
        }
    }

    /// A flank with no recorded `outward` has no sides to tell apart, so it stays
    /// symmetric — the honest answer, and what older decoded data becomes.
    func testAFlankWithoutASideStaysSymmetric() {
        let race = race()
        for from in [Vec2(50, 40), Vec2(50, -40)] {
            XCTAssertTrue(
                race.blocks(wall(.embankment, 1), car: car(atHeight: 0), movedFrom: from),
                "no outward recorded means no side to favor")
        }
    }

    /// **A railing stays symmetric.** Making rails one-way was tried and
    /// reverted: 128 of 136 rails on the eight sit on climbing pieces, so it let
    /// cars through railings almost everywhere. Only the earth is directional.
    func testARailingIsNotOneWay() {
        let race = race()
        let rail = Wall(
            from: Vec2(0, 0), to: Vec2(100, 0), height: 1, kind: .rail,
            outward: Vec2(0, 1))
        for from in [Vec2(50, 40), Vec2(50, -40)] {
            XCTAssertTrue(
                race.blocks(rail, car: car(atHeight: 1), movedFrom: from),
                "a railing must hold a deck car from both sides")
        }
    }

    /// Driving off a flank leaves the road, which is a FALL — the one-way rule
    /// only opens the barrier, gravity does the rest.
    func testLeavingAFlankFalls() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.bridgeRing), id: "t")
        // A car on the climb, pushed sideways off the flank.
        guard let flank = track.walls.first(where: { $0.kind == .embankment && $0.height > 0.3 })
        else { return XCTFail("the bridge ring must have an embankment mid-climb") }
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
        let mid = (flank.a + flank.b) * 0.5
        race.cars[0].state.position = mid + flank.outward * 2
        race.cars[0].state.height = flank.height
        race.cars[0].state.velocity = flank.outward * 200
        for _ in 0..<90 { race.advance(inputs: [PlayerID(0): .coast]) }
        XCTAssertLessThan(
            race.cars[0].state.height, flank.height,
            "leaving the flank must lose height, not slide along an invisible wall")
    }

    /// **On the real track, from every angle: no way IN, but a way OUT.**
    ///
    /// The unit tests above pin the rule on one hand-built wall; this drives all
    /// 128 embankments on the eight, because the two bugs this area has produced
    /// (the warp onto ramps, and rails going one-way) were both found on a real
    /// track while the unit tests stayed green.
    func testTheEightAdmitsNobodyThroughAFlank() {
        let track = TrackLibrary.track(id: "eight")
        let flanks = track.walls.filter { $0.kind == .embankment }
        XCTAssertGreaterThan(flanks.count, 100, "the eight is mostly climbing pieces")
        for flank in flanks where flank.outward.length > 0.001 {
            let mid = (flank.a + flank.b) * 0.5
            for speed in [200.0, 600.0] {
                var race = Race(
                    track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
                race.cars[0].state.position = mid + flank.outward * 40
                race.cars[0].state.height = 0
                race.cars[0].state.velocity = flank.outward * -speed
                for _ in 0..<40 { race.advance(inputs: [PlayerID(0): .coast]) }
                XCTAssertLessThan(
                    race.cars[0].state.height, 0.3,
                    "a ground car at \(speed) must never end up on the ramp")
            }
        }
    }

    /// And the way out is the embankment's own doing, not the railings'.
    ///
    /// The eight rails every climb, and rails are symmetric on purpose — so with
    /// them in place they, not the flank, are what holds a car on the ramp.
    /// Stripping them isolates the earth, which is what a railless ramp (the next
    /// step) will be.
    func testARaillessRampLetsYouOffTheSide() {
        var track = TrackLibrary.track(id: "eight")
        track.walls = track.walls.filter { $0.kind != .rail }
        let flanks = track.walls.filter { $0.kind == .embankment && $0.height > 0.25 }
        var escaped = 0
        for flank in flanks where flank.outward.length > 0.001 {
            var race = Race(
                track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
            let mid = (flank.a + flank.b) * 0.5
            race.cars[0].state.position = mid - flank.outward * 6
            race.cars[0].state.height = flank.height
            race.cars[0].state.velocity = flank.outward * 400
            let start = race.cars[0].state.position
            for _ in 0..<40 { race.advance(inputs: [PlayerID(0): .coast]) }
            let car = race.cars[0].state
            // Either it traveled clear of the flank, or it left and fell — a car
            // that fell to the ground has certainly left the ramp.
            if (car.position - start).dot(flank.outward) > 20 || car.height < flank.height - 0.1 {
                escaped += 1
            }
        }
        XCTAssertEqual(
            escaped, flanks.count,
            "a railless ramp must never trap a car on it — that is the whole rule")
    }

    // MARK: - A ramp carries both

    /// The compiler gives a climbing piece an embankment AND a railing, so you
    /// can neither drive into its side nor off its edge.
    func testAClimbingPieceGetsBothWalls() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.bridgeRing), id: "t")
        XCTAssertFalse(
            track.walls.filter { $0.kind == .embankment }.isEmpty,
            "a track with ramps must have embankments")
        XCTAssertFalse(
            track.walls.filter { $0.kind == .rail }.isEmpty,
            "and still have railings")
    }

    /// The reported warp: a car cannot be pushed through the railing at the
    /// gate/rail corner, where a 0.80 mouth gate is ringed by rails at 0.96–1.00.
    func testACarCannotBePushedThroughTheRailing() {
        let track = TrackLibrary.track(id: "eight")
        let corner = Vec2(157.3, 496.7)
        for step in 0..<18 {
            let angle = Double(step) * 0.35
            var race = Race(track: track, players: [PlayerID(0)])
            let direction = Vec2(angle: angle)
            race.cars[0].state.position = corner - direction * 130
            race.cars[0].state.heading = angle
            race.cars[0].state.velocity = direction * 480
            for _ in 0..<40 {
                let before = race.cars[0].state.position
                race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
                let moved = before.distance(to: race.cars[0].state.position)
                XCTAssertLessThan(moved, 30, "warped \(Int(moved)) units in one tick")
            }
        }
    }
}
