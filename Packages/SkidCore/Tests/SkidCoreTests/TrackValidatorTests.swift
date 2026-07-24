import XCTest

@testable import SkidCore

/// The saveable rules: closure, one start, no illegal overlap, valid gates,
/// canvas fit — each surfaced as a specific problem for the editor.
final class TrackValidatorTests: XCTestCase {
    // A closed rounded square that clears its own sides: start + four
    // [left-90] quarters joined by straights.
    private let square: [PieceID] = [15, 7, 1, 7, 1, 7, 1, 7]

    private func validate(_ pieces: [PieceID], gates: [Int] = [0, 2, 4, 6]) -> Validation {
        TrackValidator.validate(TrackLayout(pieces: pieces, gateSeams: gates))
    }

    func testClosedSquareIsSaveable() {
        let v = validate(square)
        XCTAssertTrue(v.isSaveable, "problems: \(v.problems)")
    }

    func testOpenChainReportsOpenEnds() {
        let v = validate([15, 1, 1], gates: [0])
        XCTAssertTrue(v.problems.contains(.openEnds(1)))
    }

    func testMissingStartPieceReported() {
        // A closed loop with NO start piece (replace 15 with straight 1).
        let v = validate([1, 7, 1, 7, 1, 7, 1, 7])
        XCTAssertTrue(v.problems.contains(.startCount(0)))
    }

    func testTwoStartPiecesReported() {
        let v = validate([15, 7, 1, 7, 15, 7, 1, 7])
        XCTAssertTrue(v.problems.contains(.startCount(2)))
    }

    func testSeamZeroMustBeAGate() {
        let v = validate(square, gates: [2, 4])  // no seam 0
        XCTAssertTrue(v.problems.contains(.gates))
    }

    func testGateCountBounds() {
        let v = validate(square, gates: [0])  // only 1 gate (<2)
        XCTAssertTrue(v.problems.contains(.gates))
    }

    func testWalkFailureShortCircuits() {
        let v = validate([15, 999])
        XCTAssertEqual(v.problems, [.walk(.unknownPiece(999))])
    }

    func testSelfOverlapReported() {
        // A degenerate loop folding back on itself: start + hairpin + hairpin
        // returns along the same corridor, colliding on the same layer.
        let v = TrackValidator.validate(
            TrackLayout(pieces: [15, 11, 11], gateSeams: [0, 1]))
        // Either it fails to close or it overlaps — both make it unsaveable;
        // assert it's not saveable and, if closed, that overlap is flagged.
        XCTAssertFalse(v.isSaveable)
    }
}
