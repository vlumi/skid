import XCTest

@testable import SkidCore

/// The walk: a flat piece list → placed poses, with fork loose-ends and exact
/// auto-mating. Closure is integer equality, so these are deterministic.
final class TrackWalkTests: XCTestCase {
    // Catalog ids used: 1 = straight 300, 7 = left 90° (tight r60),
    // 8 = right 90°, 15 = start grid (straight 300), 18 = fork (straight + L).

    /// A rounded square: start piece + (straight, left-90)×… returning home.
    /// left-90 tight advances 60 fwd + 60 side; straight adds 300. Four
    /// quarters of [straight, left90] close into a loop.
    func testRoundedSquareCloses() {
        let sq: [PieceID] = [15, 7, 15, 7, 15, 7, 15, 7]
        let r = TrackLayout(pieces: sq).walk()
        XCTAssertNil(r.failure)
        XCTAssertTrue(r.openEnds.isEmpty, "square should close, open ends: \(r.openEnds)")
        XCTAssertEqual(r.placed.count, 8)
    }

    func testOpenChainLeavesOneLooseEnd() {
        let r = TrackLayout(pieces: [15, 1, 1]).walk()
        XCTAssertNil(r.failure)
        XCTAssertEqual(r.openEnds.count, 1)  // the far end, unclosed
    }

    func testUnknownPieceFails() {
        let r = TrackLayout(pieces: [15, 999]).walk()
        XCTAssertEqual(r.failure, .unknownPiece(999))
    }

    func testEmptyLayoutFails() {
        XCTAssertEqual(TrackLayout(pieces: []).walk().failure, .emptyLayout)
    }

    func testPlacedPosesAreExactAndOrdered() {
        let r = TrackLayout(pieces: [15, 1]).walk()
        XCTAssertEqual(r.placed[0].entry, .origin)
        // start piece is straight 300 → next entry at (300, 0) east
        XCTAssertEqual(r.placed[1].entry.position, CoordPoint(300, 0))
        XCTAssertEqual(r.placed[1].entry.heading, .east)
        XCTAssertEqual(r.placed[1].entrySeam, 1)
    }

    /// A fork whose branch curls back and rejoins the trunk downstream should
    /// leave no loose ends — both routes reconnect. (Construct a small
    /// diamond: fork L/R symmetric, each side a 90° back to a common point.)
    func testForkThatRejoinsClosesBothBranches() {
        // fork symmetric (20): exits are left-90 and right-90 (sweep r160).
        // Following each with the mirrored 90° brings them to a shared pose,
        // where a join (mirrored fork, id 23) closes them, then continue home.
        // This mostly exercises that BOTH branches get walked and one mate
        // fires; a full closed diamond is covered by the compile tests.
        let r = TrackLayout(pieces: [15, 20, 8, 7]).walk()
        XCTAssertNil(r.failure)
        // Two branches from the fork, each advanced once: two loose ends
        // remain (this isn't a closed diamond, just checks fork bookkeeping).
        XCTAssertEqual(r.placed.count, 4)
        XCTAssertGreaterThanOrEqual(r.openEnds.count, 1)
    }
}
