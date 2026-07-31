import SkidCore
import XCTest

@testable import SkidKit

/// Selection is a **piece**, not a loose end. That's what gives mid-ring delete a
/// target (`removeFromRing` has been reachable-in-principle since it landed) and
/// what lets the palette build from either end.
@MainActor
final class EditorSelectionTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    private func chain() -> CouchGame {
        let game = CouchGame()
        game.editorReset()
        game.clearUndoHistory()
        for _ in 0..<3 { _ = game.editorAppend(Catalog.shortStraight) }
        return game
    }

    private func closedRing() throws -> CouchGame {
        let game = CouchGame()
        game.editorLayout = try TrackCode.decode(
            "AS0BDh8KDBEFeQUFFXoGBHgEAgQABAgMAwUC0ADwAA")
        game.clearUndoHistory()
        return game
    }

    // MARK: - which end the palette builds from

    /// The default is the appending end, so the common case needs no tap.
    func testTheTailIsTheDefaultBuildEnd() {
        let game = chain()
        XCTAssertEqual(game.editorBuildEnd, .tail)
    }

    /// Choosing the head end makes the palette prepend — that's what the arrows
    /// are for, and prepend has had no way to be reached until now.
    func testTheHeadEndPrepends() {
        let game = chain()
        let firstBefore = game.editorLayout!.pieces.first
        let countBefore = game.editorLayout!.pieces.count

        game.editorBuildEnd = .head
        XCTAssertTrue(game.editorPlace(Catalog.curve45MediumLeft))

        XCTAssertEqual(game.editorLayout!.pieces.count, countBefore + 1)
        XCTAssertEqual(game.editorLayout!.pieces.first, Catalog.curve45MediumLeft)
        XCTAssertEqual(
            game.editorLayout!.pieces[1], firstBefore,
            "the old first piece should now be second")
    }

    /// And the tail end still appends.
    func testTheTailEndAppends() {
        let game = chain()
        let countBefore = game.editorLayout!.pieces.count
        game.editorBuildEnd = .tail
        XCTAssertTrue(game.editorPlace(Catalog.curve45MediumLeft))
        XCTAssertEqual(game.editorLayout!.pieces.count, countBefore + 1)
        XCTAssertEqual(game.editorLayout!.pieces.last, Catalog.curve45MediumLeft)
    }

    /// The palette greys out per END: a piece may fit one end and not the other,
    /// so asking about the wrong one would offer placements that get refused.
    func testPlaceabilityFollowsTheChosenEnd() {
        let game = chain()
        // The fitter can never be prepended (nothing to invert) but is not a
        // palette piece either; use it as the known-refused case.
        game.editorBuildEnd = .head
        XCTAssertFalse(game.editorCanPlace(PieceCatalog.fitterPieceID))
        // A plain straight fits both ends of a short chain.
        XCTAssertTrue(game.editorCanPlace(Catalog.shortStraight))
        game.editorBuildEnd = .tail
        XCTAssertTrue(game.editorCanPlace(Catalog.shortStraight))
    }

    /// A closed ring has no free end, so no piece on it offers one to build from —
    /// which is what the arrows read, and why a ring selection is a delete target
    /// and nothing more.
    ///
    /// (Appending to a closed ring is a separate pre-existing oddity: the walk
    /// auto-mates the extra piece onto the origin inlet, so it validates but goes
    /// nowhere. Out of scope here; the UI simply offers no end to build from.)
    func testAClosedRingHasNoFreeEndsToBuildFrom() throws {
        let game = try closedRing()
        for index in game.editorLayout!.pieces.indices {
            XCTAssertTrue(
                game.editorFreeEnds(of: index).isEmpty,
                "piece \(index) of a closed ring offered a build end")
        }
    }

    /// An open chain offers its head at piece 0 and its tail at the last piece,
    /// and nothing in between.
    func testAnOpenChainOffersItsTwoEnds() {
        let game = chain()
        let last = game.editorLayout!.pieces.count - 1
        XCTAssertEqual(game.editorFreeEnds(of: 0), [.head])
        XCTAssertEqual(game.editorFreeEnds(of: last), [.tail])
        XCTAssertTrue(game.editorFreeEnds(of: 1).isEmpty)
    }

    // MARK: - selection and delete

    /// Selecting a ring piece and deleting it opens the ring there, leaving the
    /// rest of the road exactly where it was.
    func testDeletingTheSelectedRingPieceOpensTheRing() throws {
        let game = try closedRing()
        let before = game.editorLayout!.walk()
        let victim = 6
        let survivors = Set(
            before.placed.enumerated().filter { $0.offset != victim }
                .map { "\($0.element.id)@\($0.element.entry)" })

        game.editorSelection = victim
        XCTAssertTrue(game.editorDeleteSelected())

        let after = game.editorLayout!.walk()
        XCTAssertEqual(after.placed.count, before.placed.count - 1)
        XCTAssertFalse(after.openEnds.isEmpty, "the ring must open at the cut")
        for placed in after.placed {
            XCTAssertTrue(
                survivors.contains("\(placed.id)@\(placed.entry)"), "a survivor moved")
        }
    }

    /// Deleting clears the selection — it points at a piece that no longer exists,
    /// and the indices after it have all shifted.
    func testDeletingClearsTheSelection() throws {
        let game = try closedRing()
        game.editorSelection = 6
        XCTAssertTrue(game.editorDeleteSelected())
        XCTAssertNil(game.editorSelection)
    }

    /// An open chain deletes only at its ends: cutting the middle would slide the
    /// whole tail, which is never what the author means.
    func testAnOpenChainRefusesAMidChainDelete() {
        let game = chain()
        let count = game.editorLayout!.pieces.count
        game.editorSelection = 1  // neither end
        XCTAssertFalse(game.editorDeleteSelected())
        XCTAssertEqual(game.editorLayout!.pieces.count, count)

        game.editorSelection = count - 1  // the tail
        XCTAssertTrue(game.editorDeleteSelected())
        XCTAssertEqual(game.editorLayout!.pieces.count, count - 1)
    }

    /// Deleting the HEAD of a chain is prepend's inverse: the origin moves forward
    /// onto the new first piece, so the rest of the road does not jump.
    func testDeletingTheHeadKeepsTheRestInPlace() {
        let game = chain()
        game.editorBuildEnd = .head
        XCTAssertTrue(game.editorPlace(Catalog.curve45MediumRight))
        let before = game.editorLayout!.walk()

        game.editorSelection = 0
        XCTAssertTrue(game.editorDeleteSelected())

        let after = game.editorLayout!.walk()
        XCTAssertEqual(after.placed.count, before.placed.count - 1)
        for (index, placed) in after.placed.enumerated() {
            XCTAssertEqual(placed.id, before.placed[index + 1].id)
            XCTAssertEqual(
                placed.entry, before.placed[index + 1].entry, "piece \(index) moved")
        }
    }

    /// The start piece is the one piece a track cannot lose.
    func testTheStartPieceCannotBeDeleted() {
        let game = chain()
        let start = game.editorLayout!.pieces.firstIndex(of: PieceCatalog.startPieceID)
        game.editorSelection = start
        XCTAssertFalse(game.editorDeleteSelected())
        XCTAssertTrue(game.editorLayout!.pieces.contains(PieceCatalog.startPieceID))
    }

    /// A selection past the end of the list must never be acted on — the layout can
    /// shrink under it (undo, a paste, a delete).
    func testAStaleSelectionIsInert() {
        let game = chain()
        game.editorSelection = 99
        XCTAssertFalse(game.editorDeleteSelected())
        XCTAssertNil(game.editorSelectedPiece, "an out-of-range selection resolves to nothing")
    }

    /// Deleting is undoable, and one delete is one step.
    func testDeletingIsUndoable() throws {
        let game = try closedRing()
        let before = TrackCode.encode(game.editorLayout!)
        game.editorSelection = 6
        XCTAssertTrue(game.editorDeleteSelected())
        game.editorUndo()
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), before)
    }

    /// **The in-memory ring is spelled the way its code is.**
    ///
    /// Encoding normalizes, and undo snapshots are codes — so if the editor held a
    /// different spelling, an undo would silently re-spell the track and move every
    /// piece index (the selection, the gate seams, the build end) onto a different
    /// piece. Closing the loop makes it canonical, so a round-trip is a no-op.
    func testAnEditLeavesTheRingCanonicalSoUndoCannotRespellIt() throws {
        // A NON-canonical closed ring, which is what a ring built in some other
        // order looks like in memory. (A code is always canonical, so this has to
        // be respelled by hand rather than decoded.)
        let game = CouchGame()
        var respelled = try TrackCode.decode("AS0BDh8KDBEFeQUFFXoGBHgEAgQABAgMAwUC0ADwAA")
        respelled.rotate(to: 6)
        XCTAssertNotEqual(
            respelled.pieces, respelled.normalized().pieces, "fixture must be non-canonical")
        game.editorLayout = respelled
        game.clearUndoHistory()

        // Any edit settles the spelling…
        game.editorMode = .gate
        XCTAssertTrue(game.editorToggleGate(seam: 4))
        let settled = game.editorLayout!.pieces
        XCTAssertEqual(
            settled, game.editorLayout!.normalized().pieces,
            "an edit should leave the ring canonical")

        // …which is what makes a snapshot round-trip a no-op: undo restores from a
        // CODE, and codes are canonical, so a non-canonical live ring would come
        // back re-spelled — moving the selection, gate seams and build end onto
        // different pieces.
        game.editorUndo()
        XCTAssertEqual(
            game.editorLayout!.pieces, settled, "undo re-spelled the track underneath us")
    }

    /// A ring closed by BUILDING (not loaded from a code) is canonical too — that
    /// is where `finishIfClosed` normalizes.
    func testClosingALoopByBuildingMakesItCanonical() {
        let game = CouchGame()
        game.editorReset()
        game.clearUndoHistory()
        for _ in 0..<4 { _ = game.editorAppend(Catalog.curve90MediumRight) }
        guard game.editorLayout!.walk().openEnds.isEmpty else {
            return  // didn't close with this catalog; the loaded case covers the rule
        }
        XCTAssertEqual(
            game.editorLayout!.pieces, game.editorLayout!.normalized().pieces,
            "a loop should be canonical the moment it closes")
    }

    /// **Closing a loop deselects.** The piece you were building from has no free
    /// end any more, and normalizing re-indexes the ring — so a selection kept by
    /// index would silently land on whatever piece took that slot, which is how the
    /// same piece ended up selected wherever the loop was closed.
    func testClosingALoopDeselects() {
        let game = CouchGame()
        game.editorReset()
        game.clearUndoHistory()
        for _ in 0..<3 { _ = game.editorAppend(Catalog.curve90MediumRight) }
        game.editorSelection = 1
        XCTAssertNotNil(game.editorSelectedPiece)

        _ = game.editorAppend(Catalog.curve90MediumRight)
        guard game.editorLayout!.walk().openEnds.isEmpty else {
            return  // didn't close with this catalog
        }
        XCTAssertNil(game.editorSelection, "closing a loop should clear the selection")
        XCTAssertEqual(game.editorBuildEnd, .tail, "and reset the build end")
    }

    /// **Closing is the same operation from either end.** The run fills the one gap
    /// between the loose ends, so the button on the head does exactly what the one
    /// on the tail does — same pieces, same road, same code.
    func testClosingIsTheSameFromEitherEnd() {
        let builds: [[PieceID]] = [
            [Catalog.curve90MediumRight, Catalog.curve90MediumRight, Catalog.curve90MediumRight],
            [Catalog.shortStraight, Catalog.curve90TightRight, Catalog.curve90TightRight],
            [Catalog.curve45MediumRight, Catalog.curve45MediumRight, Catalog.longStraight],
        ]
        for build in builds {
            func closed(from end: CouchGame.BuildEnd) -> String? {
                let game = CouchGame()
                game.editorReset()
                game.clearUndoHistory()
                for piece in build { _ = game.editorAppend(piece) }
                let layout = game.editorLayout!
                guard let tail = layout.walk().openEnds.last,
                    case .found(let run) = layout.closingOutcome(from: tail, maxPieces: 4),
                    !run.isEmpty
                else { return nil }
                game.editorBuildEnd = end
                guard game.editorAppendRun(run) else { return "refused" }
                guard game.editorLayout!.walk().openEnds.isEmpty else { return "open" }
                return TrackCode.encode(game.editorLayout!)
            }
            guard let fromTail = closed(from: .tail) else { continue }
            XCTAssertEqual(fromTail, closed(from: .head), "the two ends disagreed")
            XCTAssertNotEqual(fromTail, "refused")
            XCTAssertNotEqual(fromTail, "open")
        }
    }

    // MARK: - markings

    /// A decal is applied in place: the geometry, the seams and every index are
    /// untouched, so only the paint changes.
    func testSettingADecalChangesNothingButThePaint() throws {
        let game = try closedRing()
        let before = game.editorLayout!
        XCTAssertTrue(game.editorSetDecal(.directionArrow, at: 3))

        let after = game.editorLayout!
        XCTAssertEqual(after.decal(at: 3), .directionArrow)
        XCTAssertEqual(after.pieces, before.pieces)
        XCTAssertEqual(after.gateSeams, before.gateSeams)
        XCTAssertEqual(after.origin, before.origin)
        XCTAssertEqual(after.walk().placed.map(\.entry), before.walk().placed.map(\.entry))
    }

    /// Clearing one works the same way, and re-applying the same decal is a no-op
    /// (so it doesn't fill the undo history with nothing).
    func testClearingADecalAndRedundantSetsAreNoOps() throws {
        let game = try closedRing()
        XCTAssertTrue(game.editorSetDecal(.directionArrow, at: 3))
        XCTAssertFalse(
            game.editorSetDecal(.directionArrow, at: 3), "setting the same decal again")
        XCTAssertTrue(game.editorSetDecal(nil, at: 3))
        XCTAssertNil(game.editorLayout!.decal(at: 3))
        XCTAssertFalse(game.editorSetDecal(nil, at: 3), "clearing an unpainted piece")
    }

    /// And it's undoable, one tap at a time.
    func testDecalsAreUndoable() throws {
        let game = try closedRing()
        let before = TrackCode.encode(game.editorLayout!)
        XCTAssertTrue(game.editorSetDecal(.directionArrow, at: 3))
        game.editorUndo()
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), before)
    }

    /// Gate mode owns map taps, so selection must not change under it.
    func testGateModeDoesNotSelect() throws {
        let game = try closedRing()
        game.editorSelection = 4
        game.editorMode = .gate
        XCTAssertNil(game.editorSelection, "entering gate mode clears the selection")
    }
}
