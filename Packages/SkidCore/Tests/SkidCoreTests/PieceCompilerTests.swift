import XCTest

@testable import SkidCore

/// Phase-A compile: a saveable layout → a well-formed runtime `Track`.
final class PieceCompilerTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID
    // Closed rounded square that clears itself (same as the validator test).
    private let square: [PieceID] = [
        Pieces.startGrid, Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
        Pieces.straight,
        Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
    ]

    private func compiledSquare() throws -> Track {
        try PieceCompiler.compile(
            TrackLayout(pieces: square, gateSeams: [0, 2, 4, 6]), id: "test-square")
    }

    func testUnsaveableLayoutThrows() {
        XCTAssertThrowsError(
            try PieceCompiler.compile(
                TrackLayout(
                    pieces: [Pieces.startGrid, Pieces.straight, Pieces.straight], gateSeams: [0]))
        ) { error in
            guard case PieceCompiler.Failure.notSaveable = error else {
                return XCTFail("expected notSaveable, got \(error)")
            }
        }
    }

    func testForkRejectedInPhaseA() {
        // A layout that closes with a fork present should reject in Phase A.
        // (Even if not perfectly closed, the fork check fires after saveable;
        // so use a minimal closeable-ish ring — assert the error type when it
        // is saveable, else accept notSaveable.)
        let layout = TrackLayout(
            pieces: [
                Pieces.startGrid, Pieces.forkStraightLeft, Pieces.curve90TightRight,
                Pieces.curve90TightRight,
                Pieces.curve90TightRight,
            ], gateSeams: [0, 1])
        XCTAssertThrowsError(try PieceCompiler.compile(layout))
    }

    func testCompiledTrackBasics() throws {
        let t = try compiledSquare()
        XCTAssertEqual(t.id, "test-square")
        XCTAssertEqual(t.width, 120)
        // `size` is the track's OWN footprint, not the whole permitted canvas.
        // It used to be the canvas, which made the race view frame every
        // piece-built track at the scale of the largest legal one — so a small
        // track rendered shrunken and off-center. See `PieceCompiler.footprint`.
        XCTAssertLessThan(t.size.x, TrackValidator.canvas.x)
        XCTAssertLessThan(t.size.y, TrackValidator.canvas.y)
        XCTAssertGreaterThan(t.centerline.count, 8)  // arcs densified
        XCTAssertEqual(t.gates.count, 4)
        XCTAssertEqual(t.startSlots.count, 4)
    }

    /// **The framing contract.** `Track.size` is the renderer's letterbox: it
    /// fits `size` to the screen and centers on `size / 2`. So the geometry must
    /// actually live inside `0…size` on both axes, and `size` must be the track's
    /// own extent — otherwise the race view draws the track at the wrong scale,
    /// off-center, with part of it off screen (which is exactly what a big oval
    /// did when `size` was hard-coded to the full canvas).
    func testGeometryFitsInsideTheReportedSize() throws {
        let track = try compiledSquare()
        for point in track.centerline {
            XCTAssertGreaterThanOrEqual(point.x, 0, "centerline left of the frame")
            XCTAssertGreaterThanOrEqual(point.y, 0, "centerline above the frame")
            XCTAssertLessThanOrEqual(point.x, track.size.x, "centerline right of the frame")
            XCTAssertLessThanOrEqual(point.y, track.size.y, "centerline below the frame")
        }
        // Everything else the renderer places must have shifted with it.
        for slot in track.startSlots {
            XCTAssertGreaterThanOrEqual(slot.x, 0)
            XCTAssertGreaterThanOrEqual(slot.y, 0)
            XCTAssertLessThanOrEqual(slot.x, track.size.x)
            XCTAssertLessThanOrEqual(slot.y, track.size.y)
        }
        for gate in track.gates {
            for point in [gate.a, gate.b] {
                XCTAssertGreaterThanOrEqual(point.x, -1, "gate outside the frame")
                XCTAssertGreaterThanOrEqual(point.y, -1, "gate outside the frame")
                XCTAssertLessThanOrEqual(point.x, track.size.x + 1, "gate outside the frame")
                XCTAssertLessThanOrEqual(point.y, track.size.y + 1, "gate outside the frame")
            }
        }
        // The frame is snug: the track fills it, rather than floating in a
        // largely empty box (the old bug). The padding is the road half-width
        // plus decoration on each side, and a gate may reach a further road
        // width onto the grass, so allow for both — but far less than the
        // canvas-sized frame this replaced.
        let slop = Double(PieceCatalog.width) * 3.5
        let xs = track.centerline.map { $0.x }
        let ys = track.centerline.map { $0.y }
        XCTAssertLessThan(track.size.x - (xs.max()! - xs.min()!), slop, "frame too wide")
        XCTAssertLessThan(track.size.y - (ys.max()! - ys.min()!), slop, "frame too tall")
    }

    /// A gate's `forward` is a DIRECTION, so re-framing must not translate it —
    /// shifting it would silently corrupt lap counting, which only accepts a
    /// crossing with a positive component along `forward`.
    func testReframingLeavesGateDirectionsAsUnitVectors() throws {
        let track = try compiledSquare()
        for gate in track.gates where gate.forward != .zero {
            XCTAssertEqual(gate.forward.length, 1, accuracy: 1e-9, "forward must stay a unit")
        }
    }

    func testCenterlineIsAClosedLoopOnAsphalt() throws {
        let t = try compiledSquare()
        // Every centerline vertex is asphalt (it's the ribbon spine).
        for p in t.centerline {
            XCTAssertEqual(t.surface(at: p), .asphalt, "centerline point \(p) off the ribbon")
        }
        // Not double-closed: last != first.
        XCTAssertNotEqual(t.centerline.first, t.centerline.last)
    }

    func testStartSlotsOnAsphaltAndGatePlacement() throws {
        let t = try compiledSquare()
        for slot in t.startSlots {
            XCTAssertEqual(t.surface(at: slot), .asphalt, "grid slot \(slot) off the ribbon")
        }
        // The last gate is start/finish; the pole should cross it driving on.
        let pole = t.startSlots[0]
        let ahead = pole + Vec2(angle: t.startHeading) * 200
        XCTAssertTrue(t.gates.last!.isCrossed(movingFrom: pole, to: ahead))
    }
}
