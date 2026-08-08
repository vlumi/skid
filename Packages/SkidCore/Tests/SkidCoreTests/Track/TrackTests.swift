import XCTest

@testable import SkidCore

final class TrackTests: XCTestCase {
    /// Asphalt on the road, grass off it. Points are taken FROM the track rather
    /// than hardcoded, so this survives the built-ins changing shape.
    func testSurfaceIsAsphaltOnTheRoadAndGrassOffIt() throws {
        let track = TrackLibrary.testRing()
        let onRoad = try XCTUnwrap(track.centerline.first)
        XCTAssertEqual(track.surface(at: onRoad), .asphalt)
        // Well off the road: grass. The frame's corner is always outside.
        XCTAssertEqual(track.surface(at: Vec2(1, 1)), .grass)
    }

    func testPatchesWinOverRibbon() throws {
        var track = TrackLibrary.testRing()
        let onRoad = try XCTUnwrap(track.centerline.first)
        track.patches = [SurfacePatch(center: onRoad, radius: 40, surface: .oil)]
        XCTAssertEqual(track.surface(at: onRoad), .oil)
        // A patch on the ground doesn't apply to a car up at deck height.
        XCTAssertEqual(track.surface(at: onRoad, height: 1), .grass)
    }

    func testStartSlotsAreOnAsphaltFacingTheStartGate() {
        let track = TrackLibrary.testRing()
        XCTAssertEqual(track.startSlots.count, PieceCompiler.Grid.slots)
        for slot in track.startSlots {
            XCTAssertEqual(track.surface(at: slot), .asphalt, "grid slot \(slot) off the ribbon")
        }
        // Driving forward from pole crosses the start/finish gate.
        let pole = track.startSlots[0]
        let ahead = pole + Vec2(angle: track.startHeading) * 300
        XCTAssertTrue(track.gates.last!.isCrossed(movingFrom: pole, to: ahead))
    }

    func testGateCrossingDetection() {
        let gate = Gate(from: Vec2(0, -50), to: Vec2(0, 50))
        XCTAssertTrue(gate.isCrossed(movingFrom: Vec2(-10, 0), to: Vec2(10, 0)))
        XCTAssertTrue(gate.isCrossed(movingFrom: Vec2(10, 20), to: Vec2(-10, 20)))
        XCTAssertFalse(gate.isCrossed(movingFrom: Vec2(-10, 60), to: Vec2(10, 60)))
        XCTAssertFalse(gate.isCrossed(movingFrom: Vec2(5, 0), to: Vec2(15, 0)))
        // Sliding along the gate line itself is not a crossing.
        XCTAssertFalse(gate.isCrossed(movingFrom: Vec2(0, -10), to: Vec2(0, 10)))
    }

    func testGatesSpanTheRibbon() {
        let track = TrackLibrary.testRing()
        XCTAssertGreaterThanOrEqual(track.gates.count, 2, "a lap needs at least two gates")
        for gate in track.gates {
            // Both gate endpoints reach past the asphalt edge.
            XCTAssertEqual(track.surface(at: gate.a), .grass)
            XCTAssertEqual(track.surface(at: gate.b), .grass)
            // But the gate's midpoint is on the ribbon.
            let mid = (gate.a + gate.b) * 0.5
            XCTAssertEqual(track.surface(at: mid), .asphalt)
        }
    }

    /// A flat built-in is fenced and nothing else — no deck rails to be found.
    func testFlatTrackHasOnlyTheBoundaryFence() {
        let track = TrackLibrary.testRing()
        XCTAssertEqual(track.walls.count, 4, "one fence, four sides")
        XCTAssertTrue(track.walls.allSatisfy { $0.kind == .boundary })
    }
}
