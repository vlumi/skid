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
        closed.append(contentsOf: run.flatMap { PieceExpansion.expand($0.id, mode: $0.pitch) })
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

    /// **The solver descends now.** A clover built on device ended half a
    /// level up, one straight from home; the search used to have no pitched
    /// candidates, so it reported "no close in 3" while a single pitched-down
    /// straight closed it. The run must find that piece — and applying it must
    /// land the ring closed on the ground.
    func testTheSolverClosesFromAHalfLevel() throws {
        let layout = try TrackCode.decode(
            TestTracks.Code.cloverOpen)
        let end = try XCTUnwrap(layout.walk().openEnds.first)
        let run = try XCTUnwrap(
            layout.closingRun(from: end), "one pitched-down short closes this")
        XCTAssertTrue(run.contains { $0.pitch == .down }, "the run must descend: \(run)")
        var closed = layout
        closed.append(contentsOf: run.flatMap { PieceExpansion.expand($0.id, mode: $0.pitch) })
        XCTAssertTrue(closed.walk().openEnds.isEmpty)
        XCTAssertEqual(closed.walk().placed.last?.exitHeight, 0)
        XCTAssertFalse(TrackValidator.validate(closed).problems.contains(.overlap))
    }

    /// Every prefix of a suggested closing run must itself be appendable — the
    /// editor applies the run one piece at a time, and each placement re-checks
    /// `canAppend`. If a mid-run step were refused, pieces would silently drop.
    func testEveryPrefixOfTheClosingRunIsAppendable() throws {
        var layout = try TrackCode.decode(Self.openCode)
        let end = try XCTUnwrap(layout.walk().openEnds.first)
        let run = try XCTUnwrap(layout.closingRun(from: end))
        for planned in run {
            XCTAssertTrue(
                TrackValidator.canAppend(planned.id, pitch: planned.pitch, to: layout),
                "mid-run piece \(planned) must be placeable on the growing prefix")
            layout.append(contentsOf: PieceExpansion.expand(planned.id, mode: planned.pitch))
        }
        XCTAssertTrue(layout.walk().openEnds.isEmpty)
    }
}
