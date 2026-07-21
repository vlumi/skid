import XCTest

@testable import SkidCore

final class TrackTests: XCTestCase {
    func testPracticeLoopSurfaces() {
        let track = TrackLibrary.practiceLoop()
        // On the bottom straight: asphalt.
        XCTAssertEqual(track.surface(at: Vec2(800, 800)), .asphalt)
        // Dead center of the world is inside the loop: grass.
        XCTAssertEqual(track.surface(at: Vec2(800, 560)), .grass)
        // Far corner of the world: grass.
        XCTAssertEqual(track.surface(at: Vec2(40, 40)), .grass)
    }

    func testPatchesWinOverRibbon() {
        var track = TrackLibrary.practiceLoop()
        track.patches = [SurfacePatch(center: Vec2(800, 800), radius: 40, surface: .oil)]
        XCTAssertEqual(track.surface(at: Vec2(800, 800)), .oil)
        XCTAssertEqual(track.surface(at: Vec2(800, 800), layer: 1), .grass)
        XCTAssertEqual(track.surface(at: Vec2(950, 800)), .asphalt)
    }

    func testStartSlotsAreOnAsphaltFacingTheStartGate() {
        let track = TrackLibrary.practiceLoop()
        XCTAssertEqual(track.startSlots.count, 4)
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
        let track = TrackLibrary.practiceLoop()
        XCTAssertEqual(track.gates.count, 4)
        for gate in track.gates {
            // Both gate endpoints reach past the asphalt edge.
            XCTAssertEqual(track.surface(at: gate.a), .grass)
            XCTAssertEqual(track.surface(at: gate.b), .grass)
            // But the gate's midpoint is on the ribbon.
            let mid = (gate.a + gate.b) * 0.5
            XCTAssertEqual(track.surface(at: mid), .asphalt)
        }
    }

    func testWallsAreOnTheCarLayer() {
        let track = TrackLibrary.practiceLoop()
        XCTAssertEqual(track.walls.count, 4)
        XCTAssertTrue(track.walls.allSatisfy { $0.layer == 0 })
    }
}
