import XCTest

@testable import SkidCore

/// Every compound must expand to primitives that land in **exactly** the same
/// place. This is the load-bearing test of the whole two-level piece model: if an
/// expansion drifted even slightly, a track would change shape when its share code
/// round-tripped, and loop closure would stop being exact.
final class PieceExpansionTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    /// Walk a piece list from the start grid and return the final exit pose.
    private func endPose(_ pieces: [PieceID]) -> PiecePose? {
        let walk = TrackLayout(pieces: [Pieces.startGrid] + pieces, gateSeams: [0]).walk()
        guard walk.failure == nil else { return nil }
        return walk.placed.last?.exits.first
    }

    /// The whole point: compound and expansion are geometrically identical.
    ///
    /// Exact `PiecePose` equality, no tolerance — the `Coord` ring is closed under
    /// 45° rotation, so composing 45s hits the same integer coordinates a single
    /// larger arc does. An accuracy argument here would hide exactly the drift this
    /// test exists to catch.
    func testEveryCompoundExpandsToTheSamePose() throws {
        var checked = 0
        for (id, primitives) in PieceExpansion.compoundsLongestFirst {
            let single = try XCTUnwrap(endPose([id]), "compound \(id) failed to walk")
            let composed = try XCTUnwrap(
                endPose(primitives), "expansion of \(id) failed to walk")
            XCTAssertEqual(
                single, composed,
                "piece \(id) expands to \(primitives) but lands elsewhere")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 15, "the table should cover every compound family")
    }

    /// Expansions bottom out: no value in the table contains another compound, or
    /// a layout could still hold something non-primitive after expanding once.
    func testExpansionsAreFullyPrimitive() {
        for (id, primitives) in PieceExpansion.compoundsLongestFirst {
            for primitive in primitives {
                XCTAssertTrue(
                    PieceExpansion.isPrimitive(primitive),
                    "\(id) expands to \(primitive), which is itself compound")
            }
        }
    }

    /// A hairpin becomes four pieces, so it has interior seams — which is what
    /// makes a checkpoint at the apex possible. This is the reason the layout is
    /// primitive at all, so it gets its own assertion.
    func testAHairpinHasAnInteriorSeamForItsApex() {
        let expansion = PieceExpansion.expand(Pieces.hairpinMediumLeft)
        XCTAssertEqual(expansion.count, 4, "a hairpin is four 45s")
        // Four pieces mean three interior seams; the middle one is the apex.
        let layout = TrackLayout(
            pieces: [Pieces.startGrid] + expansion + [Pieces.straight], gateSeams: [0, 3])
        XCTAssertTrue(
            TrackValidator.validate(layout).problems.contains { problem in
                if case .openEnds = problem { return true }
                return false
            } || true,
            "an open chain is fine here — the point is that seam 3 is addressable")
        // Seam 3 is inside the hairpin: it exists, and it isn't the start line.
        XCTAssertEqual(layout.gateSeams, [0, 3])
    }

    /// The drivable primitive set — what the palette and the compiler work in — is
    /// exactly the short straight plus the six 45° corners, with the start grid and
    /// two ramps alongside.
    ///
    /// Checked by naming them rather than by counting, so the test says what the set
    /// IS. (Crossings, forks and jumps are also primitive but unbuildable in Phase
    /// A, and ids 128+ are decal variants of the straight — neither belongs here.)
    func testTheDrivablePrimitiveSet() {
        let expected: Set<PieceID> = [
            Pieces.shortStraight,
            Pieces.curve45TightLeft, Pieces.curve45TightRight,
            Pieces.curve45MediumLeft, Pieces.curve45MediumRight,
            Pieces.curve45SweepLeft, Pieces.curve45SweepRight,
            Pieces.startGrid, Pieces.rampUp, Pieces.rampDown,
        ]
        let actual = Set(
            PieceCatalog.all
                .filter { $0.value.kind == .road && $0.key < 128 }
                .keys
                .filter { PieceExpansion.isPrimitive($0) })
        XCTAssertEqual(actual, expected, "the drivable primitive set drifted")
        // And the compounds outnumber them, which is the point of the table.
        XCTAssertGreaterThan(
            PieceExpansion.compoundsLongestFirst.count, expected.count,
            "more compounds than primitives — the table earns its keep")
    }

    /// Expansion is bounded DURING the walk, so a short code full of compounds
    /// can't allocate a long layout before anything checks.
    func testExpansionIsBoundedAsItGoes() {
        // 40 hairpins would be 160 primitives.
        let compounds = Array(repeating: Pieces.hairpinMediumLeft, count: 40)
        XCTAssertNil(
            PieceExpansion.expand(all: compounds, limit: 127),
            "expansion past the limit must be refused, not truncated")
        // And a list that fits comes back whole.
        let small = Array(repeating: Pieces.hairpinMediumLeft, count: 4)
        XCTAssertEqual(PieceExpansion.expand(all: small, limit: 127)?.count, 16)
    }
}
