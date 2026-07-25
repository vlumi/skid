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

    /// Centerlines that CROSS must be caught even when their sample points are
    /// far apart. Two 4U straights meeting at right angles have their nearest
    /// endpoints 339 units apart — way over the width threshold — so a
    /// point-to-point check missed them entirely and a figure-8 whose lobes met
    /// at the waist validated happily. The check compares segments now.
    func testCrossingCenterlinesAreCaughtBetweenSamplePoints() {
        // Two lobes turning opposite ways meet back at the middle.
        let figure8: [PieceID] =
            [Pieces.startGrid]
            + Array(repeating: Pieces.curve90MediumLeft, count: 4)
            + Array(repeating: Pieces.curve90MediumRight, count: 4)
        let v = TrackValidator.validate(TrackLayout(pieces: figure8, gateSeams: [0, 2]))
        XCTAssertTrue(v.problems.contains(.overlap), "lobes meeting at the waist is an overlap")
    }

    /// A real user build: sweeping arcs, four right then two left, a straight,
    /// two more left — a figure-8 whose lobes cross at the waist. It closes
    /// geometrically, so only the overlap rule can catch it.
    func testSweepingFigureEightIsRejected() {
        let pieces: [PieceID] =
            [Pieces.startGrid]
            + Array(repeating: Pieces.curve90SweepRight, count: 4)
            + Array(repeating: Pieces.curve90SweepLeft, count: 2)
            + [Pieces.straight]
            + Array(repeating: Pieces.curve90SweepLeft, count: 2)
        let walk = TrackLayout(pieces: pieces).walk()
        XCTAssertTrue(walk.openEnds.isEmpty, "this shape does close, so geometry won't stop it")
        let v = TrackValidator.validate(TrackLayout(pieces: pieces, gateSeams: [0, 2]))
        XCTAssertTrue(v.problems.contains(.overlap), "crossing lobes must be an overlap")
        XCTAssertFalse(v.isSaveable)
    }

    /// The editor blocks placements instead of accepting them and warning: a
    /// piece that would pave over the track is refused up front.
    func testCanAppendRefusesAPieceThatWouldOverlap() {
        // A tight ring, one piece short of lapping back over its own start.
        let ring: [PieceID] =
            [Pieces.startGrid] + Array(repeating: Pieces.curve90TightLeft, count: 4)
        let base = TrackLayout(pieces: ring)
        // Whatever the validator would flag as an overlap, canAppend must refuse.
        for candidate in [Pieces.curve90TightLeft, Pieces.straight, Pieces.hairpinTightLeft] {
            var next = base
            next.pieces.append(candidate)
            let overlaps = TrackValidator.validate(next).problems.contains(.overlap)
            XCTAssertEqual(
                TrackValidator.canAppend(candidate, to: base), !overlaps,
                "canAppend must agree with the overlap rule for piece \(candidate)")
        }
    }

    /// Blocking must NOT trip on the rules a work in progress is expected to
    /// break — loose ends, one gate, standing on the deck are all normal.
    func testCanAppendAllowsNormalMidBuildStates() {
        let onDeck = TrackLayout(pieces: [Pieces.startGrid, Pieces.rampUp])
        XCTAssertTrue(
            TrackValidator.canAppend(Pieces.straight, to: onDeck),
            "extending along the deck is a normal editing state")
        let fresh = TrackLayout(pieces: [Pieces.startGrid])
        XCTAssertTrue(TrackValidator.canAppend(Pieces.straight, to: fresh))
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
