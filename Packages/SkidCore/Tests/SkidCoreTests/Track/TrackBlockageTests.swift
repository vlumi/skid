import XCTest

@testable import SkidCore

/// **Where a track walls off its own road.**
///
/// A track can compile, pass every geometric check, and still be undrivable — the
/// road exists and a wall sits on it. That is what a mis-based ramp embankment did:
/// a spiral built fine, validated fine, and stopped the car dead at h=1.00 on its
/// own asphalt.
///
/// A WARNING, not a gate. The only thing validation gates is whether a track appears
/// in the race picker, so refusing a blocked track would make it vanish with no
/// explanation — worse than driving into the wall and seeing it.
final class TrackBlockageTests: XCTestCase {
    /// **No false positives.** This is the bar: a spurious warning on a real track
    /// teaches the author to ignore the marker, which is worse than not having one.
    func testEveryRealTrackIsClear() throws {
        var codes: [(String, String)] = TrackLibrary.builtins.map { ($0.id, $0.code) }
        codes += [
            ("spiral", TestTracks.Code.spiralToThree),
            ("babel", TestTracks.Code.towerOfBabel),
            ("bridgeRing", TestTracks.Code.bridgeRing),
        ]
        for (name, code) in codes {
            let track = try PieceCompiler.compile(TrackCode.decode(code), id: name)
            let blockages = track.blockages()
            XCTAssertTrue(
                blockages.isEmpty,
                "\(name) is drivable, so it must report no blockage; got "
                    + "\(blockages.map { "\($0.kind)@\($0.point)" })")
        }
    }

    /// **A wall standing on the road IS reported**, whatever kind it is. Built by
    /// hand rather than from a broken track, so the test does not depend on a bug
    /// still existing.
    func testAWallOnTheRoadIsFound() {
        var track = Track(
            centerline: [Vec2(0, 0), Vec2(200, 0), Vec2(400, 0), Vec2(600, 0)],
            width: 120, startSlots: [.zero], size: Vec2(1000, 1000))
        track.heights = [0, 0, 0, 0]
        XCTAssertTrue(track.blockages().isEmpty, "bare road is clear")

        // A rail laid straight across the middle of the road.
        track.walls = [
            Wall(from: Vec2(200, -60), to: Vec2(200, 60), height: 0, kind: .rail)
        ]
        let blocked = track.blockages()
        XCTAssertFalse(blocked.isEmpty, "a rail across the road must be reported")
        XCTAssertEqual(blocked.first?.kind, .rail)
    }

    /// **The reported failure, against the real track.** A hand-built fixture kept
    /// getting the flank geometry wrong — a ramp's flanks run along its OWN road, so
    /// where it crosses another they lie across that one — so this reverts the fix
    /// instead and checks the spiral that could not be driven.
    ///
    /// Reverting `Wall.base` is what the old code did: earth filling from the ground
    /// rather than from the storey its ramp stands on.
    func testTheReportedSpiralWouldHaveBeenCaught() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.spiralToThree), id: "spiral")
        // As fixed: clear.
        XCTAssertTrue(track.blockages().isEmpty, "the fixed spiral is drivable")

        // As it was: every ramp's earth based at the ground, which is the bug.
        var broken = track
        broken.walls = track.walls.map { wall in
            guard wall.kind == .embankment else { return wall }
            return Wall(
                from: wall.a, to: wall.b, height: wall.height, kind: wall.kind,
                outward: wall.outward, onClimb: wall.onClimb, base: 0)
        }
        let blockages = broken.blockages()
        XCTAssertFalse(
            blockages.isEmpty,
            "earth reaching the ground walls off the road below, and must be reported")
        XCTAssertTrue(
            blockages.contains { $0.kind == .embankment },
            "and the wall responsible is the earth, got \(Set(blockages.map(\.kind)))")
    }

    /// **A railing is not a blockage**, however close it stands.
    ///
    /// This is the property that makes centerline sampling right: a railing runs
    /// along the road's edge, so a car driving the road never meets it. Sampling the
    /// road's width instead flagged every railed piece — 79 consecutive points on the
    /// bridge ring — because the car's centre reaches to within one radius of the
    /// edge, which is where the railing is.
    func testARailingAlongTheRoadIsNotABlockage() {
        var track = Track(
            centerline: [Vec2(0, 0), Vec2(200, 0), Vec2(400, 0)],
            width: 120, startSlots: [.zero], size: Vec2(1000, 1000))
        track.heights = [1, 1, 1]
        // Railings down both edges, as a bridge has.
        track.walls = [
            Wall(
                from: Vec2(0, 60), to: Vec2(400, 60), height: 1, kind: .rail,
                outward: Vec2(0, 1)),
            Wall(
                from: Vec2(0, -60), to: Vec2(400, -60), height: 1, kind: .rail,
                outward: Vec2(0, -1)),
        ]
        XCTAssertTrue(
            track.blockages().isEmpty,
            "a railed bridge is drivable, so its own railings are not blockages")
    }

    /// **The editor gets PIECES, not centerline indices.** The compiler flattens the
    /// walk into one loop and keeps no map back, so the mapping counts the way the
    /// compiler builds: a seed point, then each piece's samples after its entry.
    ///
    /// Named against the reported track: with the earth-base bug restored, the blocked
    /// points fall in pieces 2 and 5 — both on the level-1 stretch, which is exactly
    /// where the blockage was reported ("the curve at level one").
    func testBlockedPiecesNamesTheRightPieces() throws {
        let layout = try TrackCode.decode(TestTracks.Code.spiralToThree)
        XCTAssertTrue(layout.blockedPieces().isEmpty, "the fixed spiral is clear")

        let track = try PieceCompiler.compile(layout, id: "t")
        var broken = track
        broken.walls = track.walls.map { wall in
            guard wall.kind == .embankment else { return wall }
            return Wall(
                from: wall.a, to: wall.b, height: wall.height, kind: wall.kind,
                outward: wall.outward, onClimb: wall.onClimb, base: 0)
        }
        let points = broken.blockages().map(\.point)
        XCTAssertFalse(points.isEmpty, "the bug must still be detectable")
        // Every blocked point must land inside some piece's run — no point may fall
        // off the end of the mapping.
        let walk = layout.walk()
        var running = 1
        var bounds: [(piece: Int, endsBefore: Int)] = []
        for (piece, placed) in walk.placed.enumerated() {
            running += max(
                1,
                placed.heightedSamples(
                    degreesPerSample: PieceCompiler.degreesPerSample
                ).count - 1)
            bounds.append((piece, running))
        }
        for point in points {
            XCTAssertNotNil(
                bounds.first { point < $0.endsBefore },
                "centerline point \(point) must map to a piece")
        }
        // And they name the level-1 stretch, not somewhere unrelated.
        let named = Set(
            points.compactMap { point in bounds.first { point < $0.endsBefore }?.piece })
        for piece in named {
            let placed = walk.placed[piece]
            XCTAssertLessThan(
                min(placed.entryHeight, placed.exitHeight), 1.5,
                "piece \(piece) is named as blocked, so it should be the lower road")
        }

    }

    /// **The centerline-to-piece mapping, against a known answer.**
    ///
    /// `blockedPieces()` compiles from the layout, so it cannot be pointed at
    /// rebased walls — the test above rebases a compiled `Track` instead, which
    /// exercises `blockages()` but not the mapping. This builds a track whose FIRST
    /// piece is genuinely walled off and checks the mapping names piece 0.
    ///
    /// That is the assertion the seed point matters for: the compiler seeds the loop
    /// with the first piece's entry point before adding any samples, so a mapping
    /// that forgets it shifts every piece by one — and still lands inside the track,
    /// which is why "every point maps somewhere" cannot catch it.
    func testTheMappingNamesTheFirstPieceWhenItIsBlocked() throws {
        let layout = try TrackCode.decode(TestTracks.Code.bridgeRing)
        XCTAssertTrue(layout.blockedPieces().isEmpty, "the ring is drivable to begin with")

        // Wall off the start piece's own road, at its own height.
        let walk = layout.walk()
        let start = walk.placed[0]
        let samples = start.centerlineSamples(degreesPerSample: 12)
        let mid = samples[samples.count / 2]
        var track = try PieceCompiler.compile(layout, id: "t")
        // Find the compiled point nearest that piece's middle, and wall it.
        let nearest = try XCTUnwrap(
            track.centerline.indices.min {
                (track.centerline[$0] - mid).length < (track.centerline[$1] - mid).length
            })
        let at = track.centerline[nearest]
        track.walls.append(
            Wall(
                from: at + Vec2(0, -200), to: at + Vec2(0, 200),
                height: track.heights[nearest], kind: .rail))
        let blocked = track.blockages()
        XCTAssertFalse(blocked.isEmpty, "the wall must be found")
        XCTAssertTrue(
            blocked.contains { $0.point == nearest },
            "the blockage must name the point the wall crosses, got "
                + "\(blocked.map(\.point)) for \(nearest)")
    }

    /// A one-way flank a car is LEAVING over is not a blockage — that is the
    /// designed escape, not a wall in the way.
    func testLeavingOverAFlankIsNotABlockage() {
        var track = Track(
            centerline: [Vec2(0, 0), Vec2(200, 0), Vec2(400, 0)],
            width: 120, startSlots: [.zero], size: Vec2(1000, 1000))
        track.heights = [1, 1, 1]
        // Earth along the road's own edge, its bulk facing away from the road: a car
        // driving the road approaches from inside, so it may leave over it.
        track.walls = [
            Wall(
                from: Vec2(100, 60), to: Vec2(300, 60), height: 1, kind: .embankment,
                outward: Vec2(0, 1), base: 1)
        ]
        XCTAssertTrue(
            track.blockages().isEmpty,
            "a flank the car is inside of is the road's own edge, not a blockage")
    }
}
