import XCTest

@testable import SkidCore

/// **A railing and an embankment are two different walls**, and a ramp needs
/// both. Reported from device, from both directions:
///
/// - With rails reaching the floor, one bridge edge was solid in places and
///   see-through in others (24 of 32 near-deck rails fenced the ground, 8 did
///   not) because `trunc` split 0.999 from 1.0 into different storeys. That
///   also let a car be shoved *through* a railing where neighbours disagreed.
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
