import XCTest

@testable import SkidCore

/// **Where a track sits on the canvas is not part of what it is.**
///
/// Centring used to be a button, and it could not work: `origin` is an exact `Coord`
/// so shifts are whole pieces, which leaves a residual of up to half a piece that no
/// press can improve — on a nearly centred track it correctly did nothing and looked
/// broken ("the aim button doesn't seem to do anything"). It was worse than that:
/// `max(margin, shift)` floored the shift at 60 units and `round(60/120)` is 1, so
/// every press moved the track 120 units down-right whether it needed to or not.
///
/// It belongs in `normalized()`, alongside the ring spelling and the gate-seam order —
/// arbitrary differences that must not reach the share code.
final class CenterOnCanvasTests: XCTestCase {
    private func offCentre(_ layout: TrackLayout) throws -> Vec2 {
        let used = try XCTUnwrap(
            layout.walk().footprint(padding: Double(PieceCatalog.width) / 2))
        let canvas = TrackValidator.canvas
        return Vec2(
            (used.minX + used.maxX) / 2 - canvas.x / 2,
            (used.minY + used.maxY) / 2 - canvas.y / 2)
    }

    private func moved(_ layout: TrackLayout, byPieces x: Int, _ y: Int) -> TrackLayout {
        var moved = layout
        moved.origin = PiecePose(
            position: layout.origin.position
                + CoordPoint(PieceCatalog.unit * x, PieceCatalog.unit * y),
            heading: layout.origin.heading)
        return moved
    }

    /// **The same track built anywhere on the canvas has one share code.** The point
    /// of putting centring in `normalized()`.
    func testPositionDoesNotReachTheShareCode() throws {
        let layout = try TrackCode.decode(TestTracks.Code.bridgeRing)
        let code = TrackCode.encode(layout)
        for (x, y) in [(3, 2), (-2, 1), (4, 0), (0, -1)] {
            XCTAssertEqual(
                TrackCode.encode(moved(layout, byPieces: x, y)), code,
                "moving the track \(x),\(y) pieces must not change its code")
        }
    }

    /// **Normalizing centres it**, to within the lattice it must stay on.
    func testNormalizingCentres() throws {
        let layout = try TrackCode.decode(TestTracks.Code.bridgeRing)
        let pushed = moved(layout, byPieces: 3, 2)
        XCTAssertGreaterThan(
            max(abs(try offCentre(pushed).x), abs(try offCentre(pushed).y)),
            Double(PieceCatalog.unit), "the fixture must start well off-centre")

        let after = try offCentre(pushed.normalized())
        let half = Double(PieceCatalog.unit) / 2
        XCTAssertLessThanOrEqual(abs(after.x), half + 1, "x within half a piece")
        XCTAssertLessThanOrEqual(abs(after.y), half + 1, "y within half a piece")
    }

    /// **And normalizing twice changes nothing** — the bug the old button had, where
    /// each press walked the track further away.
    func testNormalizingIsIdempotent() throws {
        for code in [TestTracks.Code.bridgeRing, TestTracks.Code.towerOfBabel] {
            let once = try TrackCode.decode(code).normalized()
            let twice = once.normalized()
            XCTAssertEqual(
                once.origin, twice.origin,
                "normalizing an already-normal track must not move it")
            XCTAssertEqual(TrackCode.encode(once), TrackCode.encode(twice))
        }
    }

    /// The road itself does not move: centring shifts where the track sits, and the
    /// compiled track is identical either way because `framed()` re-frames it.
    func testTheCompiledTrackIsUnaffected() throws {
        let layout = try TrackCode.decode(TestTracks.Code.bridgeRing)
        let here = try PieceCompiler.compile(layout, id: "t")
        let there = try PieceCompiler.compile(moved(layout, byPieces: 4, 3), id: "t")
        XCTAssertEqual(here.size, there.size, "the compiled canvas is the same size")
        XCTAssertEqual(
            here.centerline.count, there.centerline.count, "and the same road")
        for (a, b) in zip(here.centerline, there.centerline) {
            XCTAssertEqual(
                (a - b).length, 0, accuracy: 0.001,
                "framing normalises the position, so the roads coincide")
        }
    }
}
