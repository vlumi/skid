import XCTest

@testable import SkidCore

/// Where the red/white kerbs go. Real circuits kerb where the racing line
/// stresses the track — the apex (drivers cut), the corner exit on the outside
/// (running wide under power), and both sides of a chicane (you cross the road
/// through one). Straights and plain corner outsides get the thin white line.
///
/// The point of `KerbPlan` is that those positions straddle piece boundaries: an
/// exit kerb belongs to the piece *after* the corner, which no per-piece rule can
/// express. So these test the plan for a whole walked layout.
final class EdgeStyleTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    private func planFor(_ pieces: [PieceID]) -> (plan: KerbPlan, walk: WalkResult) {
        let walk = TrackLayout(pieces: pieces).walk()
        return (KerbPlan.plan(for: walk), walk)
    }

    /// Does any sample on this side of this piece carry a kerb?
    private func kerbed(_ plan: KerbPlan, piece: Int, left: Bool) -> Bool {
        guard plan.styles.indices.contains(piece) else { return false }
        return plan.styles[piece].contains { left ? $0.left == .kerb : $0.right == .kerb }
    }

    /// A ring of nothing but straights has no corner anywhere, so no kerbs.
    func testStraightsAloneAreNeverKerbed() {
        let (plan, walk) = planFor([
            Pieces.startGrid, Pieces.straight, Pieces.longStraight, Pieces.shortStraight,
        ])
        XCTAssertEqual(walk.placed.count, 4)
        for piece in walk.placed.indices {
            XCTAssertFalse(kerbed(plan, piece: piece, left: true), "piece \(piece) left")
            XCTAssertFalse(kerbed(plan, piece: piece, left: false), "piece \(piece) right")
        }
    }

    /// A corner is kerbed on its INSIDE (the apex). The model's `left` is a
    /// math-CCW turn, which renders clockwise on the y-down canvas — so a left
    /// turn's inside is on screen-right.
    func testACornerIsKerbedOnTheApex() {
        let (plan, _) = planFor([
            Pieces.startGrid, Pieces.straight, Pieces.curve90MediumLeft, Pieces.straight,
        ])
        XCTAssertTrue(kerbed(plan, piece: 2, left: false), "a left turn's apex is on screen-right")
    }

    /// The mirrored corner kerbs the other side.
    func testMirroredCornersKerbOppositeSides() {
        let (leftPlan, _) = planFor([
            Pieces.startGrid, Pieces.straight, Pieces.curve90MediumLeft, Pieces.straight,
        ])
        let (rightPlan, _) = planFor([
            Pieces.startGrid, Pieces.straight, Pieces.curve90MediumRight, Pieces.straight,
        ])
        XCTAssertTrue(kerbed(leftPlan, piece: 2, left: false))
        XCTAssertTrue(kerbed(rightPlan, piece: 2, left: true))
    }

    /// **The reason this is layout-wide**: the corner-exit kerb lands on the
    /// OUTSIDE and continues into the piece that FOLLOWS the corner. A per-piece
    /// rule can't produce this, because that piece is a plain straight.
    func testTheExitKerbContinuesIntoTheFollowingStraight() {
        let (plan, _) = planFor([
            Pieces.startGrid, Pieces.straight, Pieces.curve90MediumLeft, Pieces.longStraight,
        ])
        // The straight after the corner (piece 3) is kerbed on the corner's
        // OUTSIDE — screen-left for a left turn — despite being a straight.
        XCTAssertTrue(
            kerbed(plan, piece: 3, left: true),
            "the run-wide exit kerb must carry into the following straight")
        // …and not on the inside, which the apex already covered.
        XCTAssertFalse(kerbed(plan, piece: 3, left: false))
    }

    /// A chicane or jog bends both ways — you cross the road through it, so both
    /// edges are kerbed, as on a real circuit.
    func testChicanesAndJogsAreKerbedBothSides() {
        for crossing in [Pieces.chicaneMediumLeft, Pieces.jog240Right] {
            let (plan, _) = planFor([Pieces.startGrid, Pieces.straight, crossing, Pieces.straight])
            XCTAssertTrue(kerbed(plan, piece: 2, left: true), "piece \(crossing) left")
            XCTAssertTrue(kerbed(plan, piece: 2, left: false), "piece \(crossing) right")
        }
    }

    /// Consecutive same-direction arcs are ONE corner, so a 90° built from two
    /// 45s gets a single apex in the middle rather than two half-apexes.
    func testConsecutiveArcsFormASingleCorner() {
        let (plan, _) = planFor([
            Pieces.startGrid, Pieces.straight, Pieces.curve45MediumLeft,
            Pieces.curve45MediumLeft, Pieces.straight,
        ])
        // Somewhere across the two arcs there's an apex kerb…
        let apex = kerbed(plan, piece: 2, left: false) || kerbed(plan, piece: 3, left: false)
        XCTAssertTrue(apex, "the combined corner needs an apex kerb")
        // …and the exit kerb still lands on the straight that follows.
        XCTAssertTrue(kerbed(plan, piece: 4, left: true), "exit kerb after the combined corner")
    }

    /// The plan must line up one-for-one with the geometry samples, or the
    /// renderer would color the wrong stretches.
    func testPlanMatchesTheSampleCounts() {
        let pieces: [PieceID] = [
            Pieces.startGrid, Pieces.curve90TightLeft, Pieces.straight, Pieces.chicaneMediumRight,
            Pieces.hairpinTightLeft, Pieces.longStraight, Pieces.jog360Left,
        ]
        let (plan, walk) = planFor(pieces)
        XCTAssertEqual(plan.styles.count, walk.placed.count)
        for (index, placed) in walk.placed.enumerated() {
            XCTAssertEqual(
                plan.styles[index].count, placed.centerlineSamples().count,
                "piece \(index): one style per sample")
        }
    }

    /// Edge decoration is entirely OUTBOARD of the grip surface, so it can never
    /// narrow the road a car actually drives on.
    func testDecorationIsOutboardOfTheGripWidth() {
        XCTAssertGreaterThan(PieceCatalog.edgeLine, 0)
        XCTAssertLessThan(
            PieceCatalog.edgeLine, PieceCatalog.kerbBand,
            "the default line is thinner than a kerb")
        XCTAssertEqual(PieceCatalog.width, PieceCatalog.unit, "grip width is untouched by either")
    }
}
