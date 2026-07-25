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

    // MARK: - The closure gap readout

    /// A closed loop reports an exactly-zero gap — no epsilon, since the
    /// components come off the integer coordinates.
    func testClosedLoopReportsNoGap() {
        let layout = TrackLayout(pieces: [
            PieceCatalog.ID.startGrid, PieceCatalog.ID.curve90TightLeft, PieceCatalog.ID.straight,
            PieceCatalog.ID.curve90TightLeft, PieceCatalog.ID.straight,
            PieceCatalog.ID.curve90TightLeft, PieceCatalog.ID.straight,
            PieceCatalog.ID.curve90TightLeft,
        ])
        let walk = layout.walk()
        XCTAssertTrue(walk.openEnds.isEmpty)
        // With nothing open there's nothing to measure; measuring the final
        // exit against the origin still reports closed.
        let end = walk.placed.last!.exits[0]
        XCTAssertTrue(layout.closureGap(from: end).isClosed)
    }

    /// A gap made only of straights and 90s is pure AXIS travel: whole units,
    /// no √2 part — so straights can still close it.
    func testAxisOnlyGapIsWholeUnitsAndFixableWithStraights() {
        // Start piece (2U) alone: the loose end sits 2U east of the origin.
        let layout = TrackLayout(pieces: [PieceCatalog.ID.startGrid])
        let end = layout.walk().openEnds[0]
        let gap = layout.closureGap(from: end)
        XCTAssertFalse(gap.isClosed)
        XCTAssertFalse(gap.needsDiagonalTravel, "straights and 90s owe no √2 debt")
        XCTAssertEqual(gap.axisX, -2, "the origin is 2U back west of the end")
        XCTAssertEqual(gap.axisY, 0)
    }

    /// A single 45° curve leaves a √2 debt: straights can never close it, and
    /// the readout must say so.
    func testDiagonalGapIsFlaggedAsNeedingDiagonalTravel() {
        let layout = TrackLayout(pieces: [
            PieceCatalog.ID.startGrid, PieceCatalog.ID.curve45MediumLeft,
        ])
        let end = layout.walk().openEnds[0]
        let gap = layout.closureGap(from: end)
        XCTAssertTrue(gap.needsDiagonalTravel, "a lone 45 owes a √2 debt")
        // The gap is measured end → target, so a screen-left 45 (which turns the
        // end clockwise to step 7) needs one eighth back to face east again.
        XCTAssertEqual(gap.headingEighths, 1)
    }

    /// A mirrored chicane pair cancels its LATERAL √2 shift exactly (the y gap
    /// comes back to zero), but each chicane also advances `r√2` FORWARD, and
    /// those accumulate — so a pair still owes a forward diagonal debt. Worth
    /// pinning down: it means "chicanes close against their mirror" is about
    /// getting back on line, not about closing the loop by itself.
    func testMirroredChicanePairCancelsSidewaysButNotForward() {
        let paired = TrackLayout(pieces: [
            PieceCatalog.ID.startGrid, PieceCatalog.ID.chicaneMediumLeft,
            PieceCatalog.ID.chicaneMediumRight,
        ])
        let gap = paired.closureGap(from: paired.walk().openEnds[0])
        XCTAssertEqual(gap.headingEighths, 0, "the pair ends back on the entry heading")
        XCTAssertEqual(gap.diagonalY, 0, "the sideways √2 shift cancels exactly")
        XCTAssertNotEqual(gap.diagonalX, 0, "but the forward √2 advance accumulates")
        XCTAssertTrue(gap.needsDiagonalTravel)
    }

    /// The remedy is the actionable half of the readout: which *edit* closes a
    /// gap. A pure axis gap wants straights; a stranded √2 debt can't be fixed
    /// by adding length at all.
    func testRemedyClassifiesWhatKindOfEditIsNeeded() {
        // The start piece alone: the origin is 2U BEHIND the end, so the loop
        // has overshot — adding pieces can't help, a run must shorten.
        let axis = TrackLayout(pieces: [PieceCatalog.ID.startGrid])
        let axisEnd = axis.walk().openEnds[0]
        XCTAssertEqual(
            axis.closureGap(from: axisEnd).remedy(facing: axisEnd.heading), .tooLong)

        // Heading still off: one 45 leaves the end facing a diagonal.
        let turned = TrackLayout(pieces: [
            PieceCatalog.ID.startGrid, PieceCatalog.ID.curve45MediumLeft,
        ])
        let turnedEnd = turned.walk().openEnds[0]
        XCTAssertEqual(
            turned.closureGap(from: turnedEnd).remedy(facing: turnedEnd.heading),
            .turn(eighths: 1))

        // A closed loop needs nothing.
        let closed = TrackLayout(pieces: [
            PieceCatalog.ID.startGrid, PieceCatalog.ID.curve90TightLeft, PieceCatalog.ID.straight,
            PieceCatalog.ID.curve90TightLeft, PieceCatalog.ID.straight,
            PieceCatalog.ID.curve90TightLeft, PieceCatalog.ID.straight,
            PieceCatalog.ID.curve90TightLeft,
        ])
        let end = closed.walk().placed.last!.exits[0]
        XCTAssertEqual(closed.closureGap(from: end).remedy(facing: end.heading), .closed)
    }

    /// TWO same-handed 45s can never cancel their √2 debt, no matter how the
    /// straights are sized — the loop is unclosable by length alone, and the
    /// remedy must say "balance the diagonals" rather than "add a 45".
    /// (Regression for a real build: 45R · 90 · 90 · 90 · 45R turns a full 360°
    /// yet cannot close.)
    func testTwoSameHandedFortyFivesCannotCloseByLengthAlone() {
        func loop(straightsPerLeg: Int) -> TrackLayout {
            var pieces: [PieceID] = [PieceCatalog.ID.startGrid, PieceCatalog.ID.curve45TightRight]
            for _ in 0..<3 {
                pieces += Array(
                    repeating: PieceCatalog.ID.straight, count: straightsPerLeg)
                pieces.append(PieceCatalog.ID.curve90SweepRight)
            }
            pieces += Array(repeating: PieceCatalog.ID.straight, count: straightsPerLeg)
            pieces.append(PieceCatalog.ID.curve45TightRight)
            return TrackLayout(pieces: pieces)
        }
        for legs in 0...4 {
            let layout = loop(straightsPerLeg: legs)
            let gap = layout.closureGap(from: layout.walk().openEnds[0])
            XCTAssertEqual(gap.headingEighths, 0, "the turns total 360°, so the heading closes")
            XCTAssertEqual(
                gap.remedy(facing: layout.walk().openEnds[0].heading), .balanceDiagonals,
                "with \(legs) straights per leg the √2 debt still can't be paid by length")
        }
    }

    /// Eight same-handed 45s DO cancel — an octagon closes, and it stays closed
    /// with unequal sides as long as opposite sides match. This is the shape to
    /// reach for when a two-45 cut-corner loop won't close.
    func testOctagonClosesEvenWithOppositeSidesUnequal() {
        func octagon(legs: [Int]) -> TrackLayout {
            var pieces: [PieceID] = [PieceCatalog.ID.startGrid]
            for count in legs {
                pieces.append(PieceCatalog.ID.curve45TightRight)
                pieces += Array(repeating: PieceCatalog.ID.straight, count: count)
            }
            return TrackLayout(pieces: pieces)
        }
        // Regular, and a stretched long/short/long/short octagon.
        for legs in [[1, 1, 1, 1, 1, 1, 1, 1], [4, 1, 2, 1, 4, 1, 2, 1]] {
            XCTAssertTrue(
                octagon(legs: legs).walk().openEnds.isEmpty,
                "octagon with legs \(legs) should close")
        }
    }

    /// The suggester answers "what closes this?" concretely: any run it returns
    /// must actually close the loop, exactly. That's the property worth testing
    /// — not which pieces it picks.
    func testSuggestedClosingRunActuallyCloses() {
        // A three-quarter square: one turn and a straight short of home.
        let open: [PieceID] = [
            PieceCatalog.ID.startGrid, PieceCatalog.ID.curve90TightLeft, PieceCatalog.ID.straight,
            PieceCatalog.ID.curve90TightLeft, PieceCatalog.ID.straight,
            PieceCatalog.ID.curve90TightLeft, PieceCatalog.ID.straight,
        ]
        let layout = TrackLayout(pieces: open)
        let end = layout.walk().openEnds[0]
        guard let run = layout.closingRun(from: end, maxPieces: 3), !run.isEmpty else {
            return XCTFail("a run should exist within 3 pieces")
        }
        let closed = TrackLayout(pieces: open + run)
        XCTAssertTrue(
            closed.walk().openEnds.isEmpty,
            "the suggested run \(run) must close the loop exactly")
    }

    /// A suggested run must never route the road through pavement that's
    /// already there — "suggestable" has to mean "buildable", or the button
    /// produces tracks the validator would reject.
    func testSuggestedRunNeverCrossesExistingPavement() {
        // A long snake doubling back on itself: plenty of nearby pavement for a
        // careless search to cut through.
        let snake: [PieceID] = [
            PieceCatalog.ID.startGrid, PieceCatalog.ID.longStraight,
            PieceCatalog.ID.hairpinMediumLeft, PieceCatalog.ID.longStraight,
            PieceCatalog.ID.hairpinMediumRight, PieceCatalog.ID.longStraight,
        ]
        let layout = TrackLayout(pieces: snake)
        guard let end = layout.walk().openEnds.first else { return }
        if let run = layout.closingRun(from: end, maxPieces: 3), !run.isEmpty {
            let closed = TrackLayout(pieces: snake + run, gateSeams: [0, 2])
            let problems = TrackValidator.validate(closed).problems
            XCTAssertFalse(
                problems.contains(.overlap),
                "suggested run \(run) put the road through existing pavement")
        }
    }

    /// When no run can close a gap, the suggester says so rather than offering
    /// something that doesn't work — the two-same-handed-45 loop has no fix.
    func testSuggesterReturnsNilWhenNoShortRunCloses() {
        var pieces: [PieceID] = [PieceCatalog.ID.startGrid, PieceCatalog.ID.curve45TightRight]
        for _ in 0..<3 {
            pieces += [PieceCatalog.ID.straight, PieceCatalog.ID.curve90SweepRight]
        }
        pieces += [PieceCatalog.ID.straight, PieceCatalog.ID.curve45TightRight]
        let layout = TrackLayout(pieces: pieces)
        let end = layout.walk().openEnds[0]
        XCTAssertNil(layout.closingRun(from: end, maxPieces: 3))
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
