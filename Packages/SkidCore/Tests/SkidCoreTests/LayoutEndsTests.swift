import XCTest

@testable import SkidCore

/// **Editing both ends, and the middle of a ring.** The editor could only ever
/// grow one end; these are the model operations behind growing the other one and
/// deleting from a closed ring.
///
/// The property that matters throughout: **the road the author already drew does
/// not move.** Prepending extends backwards from the origin (so the origin moves,
/// not the track); ring deletion is rotate-then-pop, and rotation is a
/// re-spelling. Any operation that silently slid the existing geometry would be
/// worse than not offering it.
final class LayoutEndsTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    private func chain() -> TrackLayout {
        TrackLayout(
            pieces: [
                Catalog.startGrid, Catalog.shortStraight, Catalog.curve45MediumLeft,
                Catalog.longStraight,
            ],
            pitches: [.flat, .up, .up, .flat],
            gateSeams: [0, 2])
    }

    /// The clover: a closed ring with pitches, a raised baseline and
    /// self-crossing — the awkward case for anything that re-spells a ring.
    private func closedRing() throws -> TrackLayout {
        try TrackCode.decode(
            "AQ4BGR8eAQ95AwMBHgEPAwMBHgEPAwMBHgEPAwMCAwAXIwMFBLAFoAAFAQI")
    }

    // MARK: - the inverse placement

    /// Placing a piece so it ENDS at a known pose is the whole trick behind
    /// prepending, and it must be exact — the entry it reports, walked forward,
    /// has to land back on the target with no drift, or loop closure breaks.
    func testEntryPoseLeadingToAKnownExitIsExact() throws {
        let targets = [
            PiecePose.origin,
            PiecePose(position: CoordPoint(480, -240), heading: .init(3)),
            PiecePose(position: CoordPoint(-720, 960), heading: .init(6)),
        ]
        for id in [
            Catalog.shortStraight, Catalog.longStraight, Catalog.curve45MediumLeft,
            Catalog.curve45MediumRight, Catalog.curve90TightLeft, Catalog.jog240Right,
        ] {
            let piece = try XCTUnwrap(PieceCatalog.piece(id))
            for target in targets {
                let entry = try XCTUnwrap(
                    TrackLayout.entryPose(of: piece, leadingTo: target),
                    "piece \(id) has no inverse placement")
                XCTAssertEqual(
                    piece.paths[0].exit(from: entry), target,
                    "piece \(id) walked forward from its derived entry missed the target")
            }
        }
    }

    // MARK: - prepend

    /// Prepending grows the chain BACKWARDS: the new piece leads into the old
    /// first piece, so the origin moves back and everything already drawn stays
    /// exactly where it was.
    func testPrependMovesTheOriginNotTheTrack() {
        var layout = chain()
        let before = layout.walk()

        XCTAssertTrue(layout.prepend(Catalog.shortStraight, pitch: .down))

        XCTAssertEqual(layout.pieces.first, Catalog.shortStraight)
        XCTAssertEqual(layout.pieces.count, before.placed.count + 1)
        // The new piece owns the pitch it was given; the others keep theirs.
        XCTAssertEqual(layout.pitch(at: 0), .down)
        XCTAssertEqual(layout.pitch(at: 1), .flat, "the start grid")
        XCTAssertEqual(layout.pitch(at: 2), .up)
        XCTAssertEqual(layout.pitch(at: 3), .up)
        // Gate seams followed their pieces.
        XCTAssertEqual(layout.gateSeams, [1, 3])

        // Every piece that existed before sits exactly where it did.
        let after = layout.walk()
        XCTAssertNil(after.failure)
        for (index, original) in before.placed.enumerated() {
            XCTAssertEqual(after.placed[index + 1].id, original.id)
            XCTAssertEqual(
                after.placed[index + 1].entry, original.entry, "piece \(index) moved")
        }
    }

    /// The prepended piece's exit is the old origin — they are joined, not merely
    /// adjacent. (A gap here would leave two loose ends instead of one chain.)
    func testThePrependedPieceJoinsTheOldFirstPiece() {
        var layout = chain()
        let oldOrigin = layout.origin
        XCTAssertTrue(layout.prepend(Catalog.curve45MediumRight))

        let after = layout.walk()
        XCTAssertEqual(
            after.placed[0].exits[0], oldOrigin, "the new piece does not reach the old start")
        XCTAssertEqual(after.placed[1].entry, oldOrigin)
        // One loose end at each end of an open chain — no orphan in the middle.
        XCTAssertEqual(after.openEnds.count, 1)
    }

    /// A pitched prepend has to keep the track's heights where they were: the
    /// piece climbs INTO the old start, so the baseline drops by its climb rather
    /// than every later height shifting.
    func testAPitchedPrependKeepsTheExistingHeights() {
        var layout = chain()
        let before = layout.walk()
        XCTAssertTrue(layout.prepend(Catalog.shortStraight, pitch: .up))

        let after = layout.walk()
        for (index, original) in before.placed.enumerated() {
            XCTAssertEqual(
                after.placed[index + 1].entryHeight, original.entryHeight, accuracy: 1e-12,
                "piece \(index) changed height")
        }
        // The new piece climbs into the old baseline, so it starts below it.
        XCTAssertEqual(
            after.placed[0].exitHeight, before.placed[0].entryHeight, accuracy: 1e-12)
    }

    /// A compound prepends **in order**: what lands at the head must read the same
    /// way it would if appended, so a hairpin laid backwards is not silently
    /// mirrored. (The run goes in back-to-front to achieve that.)
    func testPrependingACompoundKeepsItsOrder() {
        let compound = Catalog.jog240Right
        let expanded = PieceExpansion.expand(compound, mode: .flat).map(\.id)
        XCTAssertGreaterThan(expanded.count, 1, "fixture must be a real compound")

        var layout = chain()
        XCTAssertTrue(layout.prependAll(PieceExpansion.expand(compound, mode: .flat)))
        XCTAssertEqual(
            Array(layout.pieces.prefix(expanded.count)), expanded,
            "the compound went in reversed")

        // And the shape it makes is the same one appending it would: prepending a
        // run then appending the original chain's pieces is the same road.
        let after = layout.walk()
        XCTAssertNil(after.failure)
        XCTAssertEqual(after.openEnds.count, 1, "still one open chain")
    }

    /// All or nothing: a run that cannot be placed leaves the layout untouched,
    /// so a refused prepend never leaves half a compound behind.
    func testAFailedPrependAllRollsBack() {
        var layout = chain()
        let ok = layout.prependAll([
            (id: Catalog.shortStraight, pitch: .flat),
            (id: PieceCatalog.fitterPieceID, pitch: .flat),
        ])
        XCTAssertFalse(ok)
        XCTAssertEqual(layout, chain(), "a refused run must roll back completely")
    }

    /// Refused when the piece has no exact inverse placement — better to decline
    /// than to round and break the integer loop closure everything rests on.
    func testPrependRefusesWhatItCannotPlaceExactly() {
        var layout = chain()
        // A fitter's shape lives in the layout, not the catalog, and its exit is
        // pinned to the inlet it closes onto — there is nothing to invert.
        XCTAssertFalse(layout.prepend(PieceCatalog.fitterPieceID))
        XCTAssertEqual(layout, chain(), "a refused prepend must change nothing")
    }

    // MARK: - deleting from a closed ring

    /// Delete anywhere on a ring: rotate the victim to the end and pop it. The
    /// surviving geometry stays put because rotation is a re-spelling — the payoff
    /// of the canonical-rotation groundwork.
    func testRingDeleteLeavesTheSurvivingGeometryInPlace() throws {
        let ring = try closedRing()
        let before = ring.walk()
        let victim = 4
        let survivors = before.placed.enumerated()
            .filter { $0.offset != victim }
            .map { (id: $0.element.id, entry: $0.element.entry) }

        var cut = ring
        XCTAssertTrue(cut.removeFromRing(at: victim))

        XCTAssertEqual(cut.pieces.count, ring.pieces.count - 1)
        let after = cut.walk()
        XCTAssertNil(after.failure)
        // The ring is now an open chain — two loose ends at the cut.
        XCTAssertFalse(after.openEnds.isEmpty, "cutting a ring must open it")
        // Every survivor is still at its old pose. Order is rotated (the cut
        // becomes the ends), so compare as a set of (id, entry).
        let poses = Set(after.placed.map { PosedPiece(id: $0.id, entry: $0.entry) })
        for survivor in survivors {
            XCTAssertTrue(
                poses.contains(PosedPiece(id: survivor.id, entry: survivor.entry)),
                "a surviving piece moved")
        }
    }

    /// Deleting the piece that is already last needs no rotation at all — the
    /// same operation, and it must not be a special case at the call site.
    func testRingDeleteHandlesTheLastPiece() throws {
        let ring = try closedRing()
        var cut = ring
        XCTAssertTrue(cut.removeFromRing(at: ring.pieces.count - 1))
        XCTAssertEqual(cut.pieces, Array(ring.pieces.dropLast()))
    }

    /// A track must keep its start line, and a one-piece track cannot shrink.
    func testRingDeleteRefusesTheLastPieceStanding() {
        var solo = TrackLayout(pieces: [Catalog.startGrid], gateSeams: [0])
        XCTAssertFalse(solo.removeFromRing(at: 0))
        XCTAssertEqual(solo.pieces, [Catalog.startGrid])
    }

    /// Deleting a GATED piece drops its checkpoint and leaves a valid-but-
    /// unsaveable layout — not a corrupt one. (The editor says so at save time;
    /// a warning per delete would just be noise.)
    func testDeletingAGatedPieceDropsTheCheckpointCleanly() throws {
        var ring = try closedRing()
        let gated = try XCTUnwrap(ring.gateSeams.first { $0 != 0 })
        XCTAssertTrue(ring.removeFromRing(at: gated))

        for seam in ring.gateSeams {
            XCTAssertTrue(ring.pieces.indices.contains(seam), "a gate seam outlived its piece")
        }
        XCTAssertNil(ring.walk().failure, "the layout must stay walkable")
    }

    /// **The two ends build the same road.** Growing a chain forwards from the
    /// front and backwards from the back must produce identical geometry — the
    /// shape is the piece order, not the order the author happened to lay it in.
    ///
    /// This is the operation's real contract, and it exercises the inverse
    /// placement over every piece in the run rather than one at a time.
    func testBuildingBackwardsGivesTheSameRoadAsBuildingForwards() {
        let run: [(id: PieceID, pitch: Pitch)] = [
            (Catalog.shortStraight, .flat), (Catalog.curve45MediumLeft, .up),
            (Catalog.longStraight, .up), (Catalog.curve45MediumRight, .flat),
            (Catalog.shortStraight, .down),
        ]

        // Forwards: start at the grid, append the run.
        var forwards = TrackLayout(pieces: [Catalog.startGrid], gateSeams: [0])
        forwards.append(contentsOf: run)

        // Backwards: start at the grid, prepend the run so it lands ahead of it.
        var backwards = TrackLayout(pieces: [Catalog.startGrid], gateSeams: [0])
        XCTAssertTrue(backwards.prependAll(run))

        // Same piece list (the grid moved to the end in the backwards build).
        XCTAssertEqual(backwards.pieces, run.map(\.id) + [Catalog.startGrid])
        XCTAssertEqual(forwards.pieces, [Catalog.startGrid] + run.map(\.id))

        // Same road: the run's pieces sit at the same RELATIVE poses either way.
        // Compare each build's shape as the sequence of entry poses expressed
        // relative to the run's own first piece.
        let f = forwards.walk().placed
        let b = backwards.walk().placed
        XCTAssertEqual(f.count, b.count)
        for index in 0..<run.count {
            let fromForwards = f[index + 1]  // the grid is first in this build
            let fromBackwards = b[index]  // the run is first in this one
            XCTAssertEqual(fromForwards.id, fromBackwards.id)
            XCTAssertEqual(
                fromForwards.entry.position - f[1].entry.position,
                fromBackwards.entry.position - b[0].entry.position,
                "piece \(index) sits at a different place in the backwards build")
            XCTAssertEqual(
                fromForwards.entry.heading.step - f[1].entry.heading.step,
                fromBackwards.entry.heading.step - b[0].entry.heading.step,
                "piece \(index) faces a different way in the backwards build")
            // Heights too: the run climbs the same way either way.
            XCTAssertEqual(
                fromForwards.entryHeight - f[1].entryHeight,
                fromBackwards.entryHeight - b[0].entryHeight, accuracy: 1e-12,
                "piece \(index) sits at a different height in the backwards build")
        }
    }

    /// A pose-tagged piece, for comparing survivors as a set.
    private struct PosedPiece: Hashable {
        var id: PieceID
        var entry: PiecePose
    }
}
