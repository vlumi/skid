import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Whole dashes inside each piece, ending flush with its far edge.**
///
/// The rule exists because the obvious alternative — one pattern round the ring, clipped
/// at the joins — draws a straddling dash twice, once per piece, and the halves alias
/// against each other at the seam. Ending every piece on a complete dash puts the join
/// in a GAP instead, where nothing can show.
final class LaneDashPlanTests: XCTestCase {
    /// **Every piece ends flush with a dash**, so the next one opens with a gap and the
    /// seam falls in clear road. This is the whole rule.
    func testEveryPieceEndsOnACompleteDash() {
        for length in [60.0, 120.0, 188.5, 240.0, 480.0, 47.0] {
            let dashes = LaneDashPlan.dashes(inPieceOfLength: length)
            let last = try? XCTUnwrap(dashes.last)
            XCTAssertEqual(
                last?.to ?? 0, 1.0, accuracy: 1e-9,
                "a \(length)-long piece does not end flush: \(String(describing: last))")
        }
    }

    /// **And begins with a gap**, for the same reason from the other side.
    func testEveryPieceBeginsWithAGap() {
        for length in [120.0, 188.5, 480.0] {
            let first = LaneDashPlan.dashes(inPieceOfLength: length).first
            XCTAssertGreaterThan(
                first?.from ?? 0, 0, "a \(length)-long piece opens mid-dash")
        }
    }

    /// **No dash escapes its piece.** Nothing is clipped, so nothing may need clipping.
    func testDashesStayInsideTheirPiece() {
        for length in [60.0, 120.0, 188.5, 240.0] {
            for dash in LaneDashPlan.dashes(inPieceOfLength: length) {
                XCTAssertGreaterThanOrEqual(dash.from, 0)
                XCTAssertLessThanOrEqual(dash.to, 1.0 + 1e-9)
                XCTAssertLessThan(dash.from, dash.to)
            }
        }
    }

    /// **Straights get whole dashes at the nominal period**, which is what makes a run of
    /// them share one rhythm: 1U → 2, 2U → 4, 4U → 8.
    func testStraightsGetTheExpectedDashCount() {
        let unit = Double(PieceCatalog.unit)
        for (length, expected) in [(unit, 2), (unit * 2, 4), (unit * 4, 8)] {
            XCTAssertEqual(
                LaneDashPlan.dashes(inPieceOfLength: length).count, expected,
                "a \(length / unit)U straight should hold \(expected) dashes")
        }
    }

    /// A curve's period stretches a little to fit whole dashes — the point being that it
    /// still fits WHOLE ones rather than ending on a stub.
    func testACurveFitsWholeDashesByStretching() {
        let dashes = LaneDashPlan.dashes(inPieceOfLength: 188.5)
        XCTAssertEqual(dashes.count, 3)
        let period = 188.5 / 3
        XCTAssertEqual(period, 62.83, accuracy: 0.01)
        // Within a few percent of the nominal 60, so the eye reads one rhythm.
        XCTAssertLessThan(abs(period - LaneDashPlan.period) / LaneDashPlan.period, 0.06)
    }

    /// **A very short piece still gets one dash** rather than none.
    func testAShortPieceStillGetsADash() {
        XCTAssertEqual(LaneDashPlan.dashes(inPieceOfLength: 20).count, 1)
        XCTAssertTrue(LaneDashPlan.dashes(inPieceOfLength: 0).isEmpty)
    }

    /// A dash is shorter than its gap, which is what makes it read as road marking.
    func testADashIsShorterThanItsGap() {
        let dashes = LaneDashPlan.dashes(inPieceOfLength: 240)
        let dash = dashes[0].to - dashes[0].from
        let gap = dashes[1].from - dashes[0].to
        XCTAssertLessThan(dash, gap)
    }

    /// The start grid, gaps and warps carry no dashes.
    func testSomePiecesCarryNoDashes() {
        let walk = TrackLayout(
            pieces: [PieceCatalog.startPieceID, 1, PieceCatalog.ID.gap]
        ).walk()
        XCTAssertFalse(LaneDashPlan.paints(walk.placed[0]), "the start grid is not dashed")
        XCTAssertTrue(LaneDashPlan.paints(walk.placed[1]))
        XCTAssertFalse(LaneDashPlan.paints(walk.placed[2]), "a gap has no road to paint")
    }
}
