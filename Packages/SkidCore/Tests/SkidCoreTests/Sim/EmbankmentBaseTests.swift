import XCTest

@testable import SkidCore

/// **Earth fills from the storey its ramp stands on, not from the ground.**
///
/// An embankment stops a car driving into a ramp's flank. It used to be solid from
/// height 0 upward, which was indistinguishable while there was one deck — nothing
/// could be underneath a ramp. With three storeys a 2→3 ramp's earth spanned 0…3
/// and walled off the level-1 road passing beneath it: reported as a track that
/// built fine and could not be driven, the car stopped dead at h=1.00 on its own
/// asphalt with `hits this tick 1`.
final class EmbankmentBaseTests: XCTestCase {
    private func race() -> Race {
        Race(
            track: Track(
                centerline: [Vec2(-500, 0), Vec2(500, 0)], width: 120,
                startSlots: [.zero], size: Vec2(1000, 1000)),
            players: [PlayerID(0)])
    }

    private func car(atHeight height: Double) -> CarState {
        var car = CarState(position: .zero)
        car.height = height
        return car
    }

    /// A 2→3 ramp's earth leaves the road at level 1 clear.
    func testEarthAboveDoesNotBlockTheRoadBelow() {
        let race = race()
        let upper = Wall(
            from: Vec2(0, 0), to: Vec2(100, 0), height: 2.5, kind: .embankment,
            outward: Vec2(0, 1), base: 2)
        XCTAssertFalse(
            race.blocks(upper, car: car(atHeight: 1), movedFrom: Vec2(50, 40)),
            "a car a whole storey below the ramp's base must pass underneath")
        XCTAssertFalse(
            race.blocks(upper, car: car(atHeight: 0), movedFrom: Vec2(50, 40)),
            "and so must a ground car")
    }

    /// But it still stops a car ON the storey the ramp stands on — that is the
    /// anti-warp rule, and the whole reason the earth exists.
    func testEarthStillBlocksFromItsOwnBase() {
        let race = race()
        let upper = Wall(
            from: Vec2(0, 0), to: Vec2(100, 0), height: 2.5, kind: .embankment,
            outward: Vec2(0, 1), base: 2)
        for height in [2.0, 2.25, 2.5] {
            XCTAssertTrue(
                race.blocks(upper, car: car(atHeight: height), movedFrom: Vec2(50, 40)),
                "a car at \(height) is beside this ramp's flank and must be stopped")
        }
    }

    /// A ground ramp is unchanged: base 0, so it fences the ground exactly as before.
    func testAGroundRampIsUnchanged() {
        let race = race()
        let ground = Wall(
            from: Vec2(0, 0), to: Vec2(100, 0), height: 0.5, kind: .embankment,
            outward: Vec2(0, 1), base: 0)
        XCTAssertTrue(race.blocks(ground, car: car(atHeight: 0), movedFrom: Vec2(50, 40)))
        XCTAssertFalse(
            race.blocks(ground, car: car(atHeight: 2), movedFrom: Vec2(50, 40)),
            "a car well above it still runs clear")
    }

    /// The compiler records the base from the climb's lower end, rounded down to a
    /// whole storey — a half-climb from 2.0 to 2.5 still stands on the level-2 deck.
    func testTheCompilerRecordsTheBase() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.spiralToThree), id: "spiral")
        let flanks = track.walls.filter { $0.kind == .embankment }
        XCTAssertFalse(flanks.isEmpty)
        for flank in flanks {
            XCTAssertEqual(
                flank.base, flank.base.rounded(.down), accuracy: 1e-9,
                "a base is a whole storey")
            XCTAssertLessThanOrEqual(
                flank.base, flank.height + Track.reachTolerance,
                "and never above the road it carries")
        }
        // The spiral climbs to 3, so some earth must stand above the ground.
        XCTAssertTrue(
            flanks.contains { $0.base > 0.5 },
            "a spiral to height 3 has ramps standing on upper storeys")
    }

    /// **On the reported track, nothing blocks the road at level 1.** The symptom,
    /// as a test.
    func testTheReportedTrackIsDrivableAtLevelOne() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.spiralToThree), id: "spiral")
        let race = Race(track: track, players: [PlayerID(0)])
        let count = track.centerline.count
        for index in track.centerline.indices where abs(track.heights[index] - 1) < 0.1 {
            let point = track.centerline[index]
            let previous = track.centerline[(index - 1 + count) % count]
            var car = CarState(position: point)
            car.height = track.heights[index]
            let blocking = track.walls.filter {
                race.blocks($0, car: car, movedFrom: previous)
                    && point.distance(toSegment: $0.a, $0.b) < CarGeometry.radius + 30
            }
            XCTAssertTrue(
                blocking.isEmpty,
                "a car driving the level-1 road at \(point) must not be walled in; "
                    + "blocked by \(blocking.map { "\($0.kind)@\($0.height)" })")
        }
    }

    /// And the anti-warp property survives on real tracks: a car cannot climb a
    /// ramp by driving at its flank.
    func testNoWarpOntoARampFlank() throws {
        for code in [TestTracks.Code.spiralToThree, TestTracks.Code.bridgeRing] {
            let track = try PieceCompiler.compile(TrackCode.decode(code), id: "t")
            for flank in track.walls
            where flank.kind == .embankment && flank.outward.length > 0.001 {
                var race = Race(
                    track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
                let mid = (flank.a + flank.b) * 0.5
                race.cars[0].state.position = mid + flank.outward * 40
                race.cars[0].state.height = flank.base
                race.cars[0].state.velocity = flank.outward * -600
                for _ in 0..<40 { race.advance(inputs: [PlayerID(0): .coast]) }
                XCTAssertLessThan(
                    race.cars[0].state.height, flank.base + 0.3,
                    "a car must not climb onto a ramp by driving at its flank")
            }
        }
    }
}
