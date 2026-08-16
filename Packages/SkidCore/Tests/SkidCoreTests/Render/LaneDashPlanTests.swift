import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Whole dashes, centred in each piece with half a gap at each end.**
///
/// Two neighbours then contribute half a gap each, so the seam carries exactly one
/// normal gap: the rhythm is unbroken, and no dash goes near an edge. That last part is
/// the bug being avoided — a piece's asphalt is drawn slightly past its own ends, so
/// anything painted flush to a boundary is covered by the next piece's road.
final class LaneDashPlanTests: XCTestCase {
    /// **The run is symmetric**: the space before the first dash equals the space after
    /// the last. This is the whole rule — it is what makes two neighbours add up to one
    /// normal gap at the seam.
    func testTheRunIsCentredInThePiece() {
        for length in [60.0, 120.0, 188.5, 240.0, 480.0, 47.0] {
            let dashes = LaneDashPlan.dashes(inPieceOfLength: length)
            guard let first = dashes.first, let last = dashes.last else {
                return XCTFail("a \(length)-long piece got no dashes")
            }
            XCTAssertEqual(
                first.from, 1 - last.to, accuracy: 1e-9,
                "a \(length)-long piece is not centred: leads \(first.from), "
                    + "trails \(1 - last.to)")
        }
    }

    /// **Neither end is flush**, so the seam overlap cannot clip a dash.
    func testNoDashTouchesAnEdge() {
        for length in [120.0, 188.5, 480.0] {
            let dashes = LaneDashPlan.dashes(inPieceOfLength: length)
            XCTAssertGreaterThan(dashes.first?.from ?? 0, 0, "opens flush at \(length)")
            XCTAssertLessThan(dashes.last?.to ?? 1, 1, "ends flush at \(length)")
        }
    }

    /// **Two neighbours make one normal gap.** Half a gap trailing plus half a gap
    /// leading is a full one, so a join is indistinguishable from any other gap.
    func testTwoNeighboursMakeOneNormalGap() {
        let length = 120.0
        let dashes = LaneDashPlan.dashes(inPieceOfLength: length)
        let trailing = (1 - (dashes.last?.to ?? 1)) * length
        let leading = (dashes.first?.from ?? 0) * length
        let interior = ((dashes[1].from - dashes[0].to)) * length
        XCTAssertEqual(
            trailing + leading, interior, accuracy: 1e-9,
            "the seam gap (\(trailing + leading)) differs from a normal one (\(interior))")
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
