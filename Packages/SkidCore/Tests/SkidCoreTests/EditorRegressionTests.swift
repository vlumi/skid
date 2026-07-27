import XCTest

@testable import SkidCore

/// Regressions caught on a real device with a real 41-piece design, pasted here
/// as the share codes the editor produced. Both bugs came from the same root:
/// overlap legality was decided per PIECE PAIR with stacked exemptions, and the
/// join region — the chain's end approaching the start — fell through every one
/// of them once layouts became primitives.
final class EditorRegressionTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    /// The design as built on device: open, 41 primitives, loose end one tight
    /// 90° right away from closing onto the start.
    private static let openCode = "AfgBDx8BDAICDAIMARIPAgsBCgIBAAMFAtAAeAI"
    /// The same design closed by hand (the author extended it further up and
    /// brought it home) — proof the shape itself was always legal.
    private static let closedCode = "AREBEB8BDAICDAIMARIPAgsCEAECBAALFyMDBQYYAWgC"

    /// **The right turn must be offered.** On the open design, the turn that
    /// closes the loop was greyed out: the closing corner runs beside the start
    /// piece before it lands, and that approach read as a self-overlap.
    func testTheClosingTurnIsAppendable() throws {
        let layout = try TrackCode.decode(Self.openCode)
        XCTAssertEqual(layout.walk().openEnds.count, 1)
        // Both the first half of the closing corner and the whole corner.
        XCTAssertTrue(
            TrackValidator.canAppend(Pieces.curve45TightRight, to: layout),
            "the first 45° of the closing corner must be placeable")
        XCTAssertTrue(
            TrackValidator.canAppend(Pieces.curve90TightRight, to: layout),
            "the closing 90° must be placeable")
        // And the turn away from the join stays open too.
        XCTAssertTrue(TrackValidator.canAppend(Pieces.curve45TightLeft, to: layout))
    }

    /// **"Close it" must find the one-corner closure.** The search's clearance
    /// snapshot excluded only the first and last piece of the chain; a primitive
    /// closing run legitimately hugs more of both ends than that, so every
    /// candidate was rejected and the button never appeared.
    func testCloseItFindsTheOneCornerClosure() throws {
        let layout = try TrackCode.decode(Self.openCode)
        let end = try XCTUnwrap(layout.walk().openEnds.first)
        let run = try XCTUnwrap(
            layout.closingRun(from: end), "a tight 90° right closes this exactly")
        var closed = layout
        closed.pieces += run
        let walk = closed.walk()
        XCTAssertTrue(walk.openEnds.isEmpty, "the suggested run must actually close")
        XCTAssertFalse(
            TrackValidator.validate(closed).problems.contains(.overlap),
            "and the closed result must not read as overlapping itself")
    }

    /// The author's own hand-closed variant is a valid track: no overlap, ring
    /// closed. If this flags, the rule is wrong, not the track.
    func testTheHandClosedDesignValidates() throws {
        let layout = try TrackCode.decode(Self.closedCode)
        let walk = layout.walk()
        XCTAssertNil(walk.failure)
        XCTAssertTrue(walk.openEnds.isEmpty)
        XCTAssertFalse(TrackValidator.validate(layout).problems.contains(.overlap))
    }

    /// Every prefix of a suggested closing run must itself be appendable — the
    /// editor applies the run one piece at a time, and each placement re-checks
    /// `canAppend`. If a mid-run step were refused, pieces would silently drop.
    func testEveryPrefixOfTheClosingRunIsAppendable() throws {
        var layout = try TrackCode.decode(Self.openCode)
        let end = try XCTUnwrap(layout.walk().openEnds.first)
        let run = try XCTUnwrap(layout.closingRun(from: end))
        for id in run {
            XCTAssertTrue(
                TrackValidator.canAppend(id, to: layout),
                "mid-run piece \(id) must be placeable on the growing prefix")
            layout.append(contentsOf: PieceExpansion.expand(id))
        }
        XCTAssertTrue(layout.walk().openEnds.isEmpty)
    }
}
