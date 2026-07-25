import XCTest

@testable import SkidCore

/// Piece segment geometry — arcs especially — must land on exact coordinates
/// and match hand-computed endpoints, so the walk and closure stay exact.
final class PieceGeometryTests: XCTestCase {
    private func exit(_ seg: Piece.Segment, from: PiecePose = .origin) -> PiecePose {
        seg.exit(from: from)
    }

    func testLeft90FromEast() {
        // r=100, left 90°: centre (0,100), exit (100,100) heading north.
        let e = exit(.arc(radius: 100, eighths: 2, left: true))
        XCTAssertEqual(e.position, CoordPoint(100, 100))
        XCTAssertEqual(e.heading, Heading(2))  // north
    }

    func testRight90FromEast() {
        // r=100, right 90°: centre (0,-100), exit (100,-100) heading south.
        let e = exit(.arc(radius: 100, eighths: 2, left: false))
        XCTAssertEqual(e.position, CoordPoint(100, -100))
        XCTAssertEqual(e.heading, Heading(6))  // south
    }

    func testLeft45FromEastLandsExactDiagonal() {
        // r=100, left 45°: exit heading NE; position uses √2/2 exactly.
        let e = exit(.arc(radius: 100, eighths: 1, left: true))
        XCTAssertEqual(e.heading, Heading(1))  // NE
        // centre (0,100); radial centre→entry = south (heading 6), swept left
        // 45° → SE (heading 7); exit = (0,100) + 100·SE-unit.
        // SE unit = (√2/2, -√2/2) = Coord(a:0,b:1),(a:0,b:-1).
        XCTAssertEqual(e.position.x, Coord(a: 0, b: 100))  // 100·√2/2
        XCTAssertEqual(e.position.y, Coord(a: 200, b: -100))  // 100 − 100·√2/2
    }

    func testTwo45ArcsEqualOne90() {
        // Composing two left-45 arcs should reach the same pose as one left-90
        // of the same radius — exact.
        let one90 = exit(.arc(radius: 160, eighths: 2, left: true))
        let first45 = exit(.arc(radius: 160, eighths: 1, left: true))
        let two45 = exit(.arc(radius: 160, eighths: 1, left: true), from: first45)
        XCTAssertEqual(two45.position, one90.position)
        XCTAssertEqual(two45.heading, one90.heading)
    }

    func testHairpin180IsTwo90s() {
        // A 180° left turn (4 eighths) reverses heading and offsets by 2r
        // sideways. From east at origin: exit heading west, position (0, 2r).
        let e = exit(.arc(radius: 60, eighths: 4, left: true))
        XCTAssertEqual(e.heading, Heading(4))  // west
        XCTAssertEqual(e.position, CoordPoint(0, 120))
    }

    func testLeftThenRightIsAnSCurve() {
        // Left 90 then right 90 (an S): net heading unchanged (east). Each
        // 90° arc advances +r forward and +r sideways, so the S climbs 2r up
        // and runs 2r forward: (200, 200) for r=100.
        let l = exit(.arc(radius: 100, eighths: 2, left: true))
        let s = exit(.arc(radius: 100, eighths: 2, left: false), from: l)
        XCTAssertEqual(s.heading, .east)
        XCTAssertEqual(s.position, CoordPoint(200, 200))
    }

    // MARK: - The unit system

    /// Every catalog dimension must be a whole multiple of the base unit — the
    /// property the whole meshing guarantee rests on.
    func testEveryCatalogDimensionIsAWholeNumberOfUnits() {
        let unit = PieceCatalog.unit
        for (id, piece) in PieceCatalog.all {
            for segment in piece.paths.flatMap({ $0 }) {
                switch segment {
                case .straight(let length):
                    XCTAssertEqual(
                        length % unit, 0, "piece \(id): straight \(length) is not a whole unit")
                case .arc(let radius, _, _):
                    XCTAssertEqual(
                        radius % unit, 0, "piece \(id): radius \(radius) is not a whole unit")
                    XCTAssertGreaterThanOrEqual(
                        radius, PieceCatalog.tightRadius,
                        "piece \(id): radius \(radius) is below the tight minimum")
                }
            }
        }
    }

    /// The tight radius must exceed half the road width, or the inner edge
    /// collapses to a pivot point instead of sweeping a real arc.
    func testTightRadiusLeavesARealInnerArc() {
        XCTAssertGreaterThan(PieceCatalog.tightRadius, PieceCatalog.width / 2)
        XCTAssertEqual(PieceCatalog.tightRadius - PieceCatalog.width / 2, PieceCatalog.unit / 2)
    }

    /// Radii double: tight : medium : sweep = 1 : 2 : 4, all in units.
    func testRadiiFormTheDoublingFamily() {
        XCTAssertEqual(PieceCatalog.tightRadius, PieceCatalog.unit)
        XCTAssertEqual(PieceCatalog.mediumRadius, 2 * PieceCatalog.unit)
        XCTAssertEqual(PieceCatalog.sweepRadius, 4 * PieceCatalog.unit)
    }

    /// A lane jog ends on the ENTRY heading, shifted sideways by exactly
    /// r_a + r_b — a whole number of units (grid-clean), which is what makes
    /// jogs the radius bridges. 240 jog: 2×tight. 360 jog: tight + medium.
    func testLaneJogsShiftAWholeNumberOfUnitsAndKeepTheHeading() {
        for (id, expected) in [
            (PieceCatalog.ID.jog240Left, 2 * PieceCatalog.tightRadius),
            (PieceCatalog.ID.jog360Left, PieceCatalog.tightRadius + PieceCatalog.mediumRadius),
        ] {
            let piece = PieceCatalog.piece(id)!
            let exit = piece.paths[0].exit(from: .origin)
            XCTAssertEqual(exit.heading, .east, "jog \(id) must end on the entry heading")
            // Screen-left jog: forward advance and lateral shift both r_a + r_b.
            XCTAssertEqual(exit.position.x, Coord(expected), "jog \(id) advance")
            XCTAssertEqual(
                exit.position.y, Coord(-expected), "jog \(id) lateral shift (screen-left = −y)")
            XCTAssertEqual(expected % PieceCatalog.unit, 0, "jog \(id) shift must be whole units")
        }
    }

    /// An S-chicane also returns to the entry heading, but its shift is
    /// r(2−√2) — irrational, so it is NOT on the unit grid and must close
    /// against a mirrored chicane rather than with straights.
    func testChicaneReturnsToEntryHeadingWithAnOffGridShift() {
        let r = PieceCatalog.tightRadius
        let piece = PieceCatalog.piece(PieceCatalog.ID.chicaneTightLeft)!
        let exit = piece.paths[0].exit(from: .origin)
        XCTAssertEqual(exit.heading, .east)
        // Lateral shift magnitude = r(2 − √2); a √2 term means b ≠ 0 (off-grid).
        XCTAssertNotEqual(exit.position.y.b, 0, "a chicane's shift must carry a √2 part")
        XCTAssertEqual(
            abs(exit.position.y.value), Double(r) * (2 - 2.0.squareRoot()), accuracy: 1e-9)
    }

    /// A mirrored chicane pair cancels the √2 debt exactly and lands back on
    /// the unit grid — the pairing rule the doc promises.
    func testMirroredChicanesCancelExactly() {
        let left = PieceCatalog.piece(PieceCatalog.ID.chicaneMediumLeft)!
        let right = PieceCatalog.piece(PieceCatalog.ID.chicaneMediumRight)!
        let mid = left.paths[0].exit(from: .origin)
        let end = right.paths[0].exit(from: mid)
        XCTAssertEqual(end.heading, .east)
        XCTAssertEqual(end.position.y, .zero, "a chicane and its mirror must cancel the shift")
        XCTAssertEqual(end.position.y.b, 0, "no √2 residue may survive the pair")
    }

    /// The 2×2 starting grid has to fit on the start piece behind the line —
    /// the one place a shortened piece length could silently push cars off the
    /// ribbon, so it's asserted rather than assumed.
    func testStartingGridFitsOnTheStartPiece() {
        let piece = PieceCatalog.piece(PieceCatalog.startPieceID)!
        guard case .straight(let length) = piece.paths[0][0] else {
            return XCTFail("the start piece must be a straight")
        }
        XCTAssertGreaterThan(
            Double(length), PieceCompiler.Grid.depth,
            "the grid is \(PieceCompiler.Grid.depth) deep but the start piece is only \(length)")
        // The stagger must also stay within the ribbon's half-width.
        XCTAssertLessThan(
            PieceCompiler.Grid.lateral + CarGeometry.width / 2, Double(PieceCatalog.width) / 2,
            "a staggered car must stay on the asphalt")
    }

    /// Chaining is what makes the compound pieces possible: a chicane piece
    /// must reach exactly what its two arcs reach placed one after the other.
    func testChainedPathMatchesPlacingTheSegmentsInSequence() {
        let piece = PieceCatalog.piece(PieceCatalog.ID.chicaneSweepRight)!
        let chain = piece.paths[0]
        XCTAssertEqual(chain.count, 2, "a chicane is two arcs")
        let manual = chain[1].exit(from: chain[0].exit(from: .origin))
        XCTAssertEqual(chain.exit(from: .origin), manual)
    }
}
