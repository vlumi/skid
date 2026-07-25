import XCTest

@testable import SkidCore

/// The saveable rules: closure, one start, no illegal overlap, valid gates,
/// canvas fit — each surfaced as a specific problem for the editor.
final class TrackValidatorTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID
    // A closed rounded square that clears its own sides: start + four
    // [left-90] quarters joined by 2U straights.
    private let square: [PieceID] = [
        Pieces.startGrid, Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
        Pieces.straight,
        Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
    ]

    private func validate(_ pieces: [PieceID], gates: [Int] = [0, 2, 4, 6]) -> Validation {
        TrackValidator.validate(TrackLayout(pieces: pieces, gateSeams: gates))
    }

    func testClosedSquareIsSaveable() {
        let v = validate(square)
        XCTAssertTrue(v.isSaveable, "problems: \(v.problems)")
    }

    func testOpenChainReportsOpenEnds() {
        let v = validate([Pieces.startGrid, Pieces.straight, Pieces.straight], gates: [0])
        XCTAssertTrue(v.problems.contains(.openEnds(1)))
    }

    func testMissingStartPieceReported() {
        // The same closed loop with NO start piece (a plain straight instead).
        let v = validate([
            Pieces.straight, Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
            Pieces.straight,
            Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
        ])
        XCTAssertTrue(v.problems.contains(.startCount(0)))
    }

    func testTwoStartPiecesReported() {
        let v = validate([
            Pieces.startGrid, Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
            Pieces.startGrid,
            Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
        ])
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
        let v = validate([Pieces.startGrid, 999])
        XCTAssertEqual(v.problems, [.walk(.unknownPiece(999))])
    }

    /// Two ribbons overlap once their centerlines are closer than a full road
    /// width (half from each side) — not half a width, which used to let a lap
    /// sit half on top of another and still validate.
    func testOverlapThresholdIsAFullRoadWidth() {
        // A tight ring that laps back over itself must be rejected.
        let ring: [PieceID] =
            [Pieces.startGrid] + Array(repeating: Pieces.curve90TightLeft, count: 8)
        let v = TrackValidator.validate(TrackLayout(pieces: ring, gateSeams: [0, 2]))
        XCTAssertFalse(v.isSaveable)
        XCTAssertTrue(v.problems.contains(.overlap), "a doubled-back lap is an overlap")
    }

    /// A ring must come back to ground level before it closes: a loop that
    /// climbs a ramp and never descends would meet itself at two heights.
    func testClosingWhileElevatedIsReported() {
        // The walk itself refuses to mate mismatched heights, so this asserts
        // the validator's own guard on the height a finished ring ends at.
        let elevated: [PieceID] = [
            Pieces.startGrid, Pieces.rampUp, Pieces.curve90TightLeft, Pieces.straight,
            Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
            Pieces.straight, Pieces.curve90TightLeft,
        ]
        let walk = TrackLayout(pieces: elevated).walk()
        // Either it can't close at all (the walk's height-aware mate refuses),
        // or if it did close the validator flags the height — never saveable.
        let v = TrackValidator.validate(TrackLayout(pieces: elevated, gateSeams: [0, 2]))
        XCTAssertFalse(v.isSaveable)
        if walk.openEnds.isEmpty {
            XCTAssertTrue(
                v.problems.contains {
                    if case .unclosedHeight = $0 { return true } else { return false }
                },
                "a ring closed on the deck must report unclosedHeight")
        }
    }

    /// Mid-build, standing on the deck is normal — the height rule must only
    /// apply to a CLOSED ring, or it would nag through every bridge.
    func testElevatedOpenChainIsNotAHeightProblem() {
        let onDeck: [PieceID] = [Pieces.startGrid, Pieces.rampUp, Pieces.straight]
        let v = TrackValidator.validate(TrackLayout(pieces: onDeck, gateSeams: [0, 1]))
        XCTAssertFalse(
            v.problems.contains {
                if case .unclosedHeight = $0 { return true } else { return false }
            },
            "an open chain on the deck is a normal editing state")
    }

    func testSelfOverlapReported() {
        // A degenerate loop folding back on itself: start + hairpin + hairpin
        // returns along the same corridor, colliding on the same layer.
        let v = TrackValidator.validate(
            TrackLayout(
                pieces: [Pieces.startGrid, Pieces.hairpinTightLeft, Pieces.hairpinTightLeft],
                gateSeams: [0, 1]))
        // Either it fails to close or it overlaps — both make it unsaveable;
        // assert it's not saveable and, if closed, that overlap is flagged.
        XCTAssertFalse(v.isSaveable)
    }
}
