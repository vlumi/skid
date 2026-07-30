import SkidCore
import XCTest

@testable import SkidKit

/// **Undo, with a long history.** The operations are tiny — a whole layout encodes
/// to well under 100 bytes — so the stack holds encoded snapshots and restoring is
/// just a decode. Delete-anywhere is what makes this necessary: destructive
/// mistakes became easy, and undo is what makes that acceptable.
///
/// The invariant worth stating: **undo restores byte-for-byte.** A share code is
/// an identity, so "the same track" is a testable claim rather than a vibe.
@MainActor
final class EditorUndoTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    private func editing() -> CouchGame {
        let game = CouchGame()
        game.editorReset()
        return game
    }

    /// The baseline: an edit is undoable, and undoing it restores the exact code.
    func testUndoRestoresThePreviousCodeExactly() {
        let game = editing()
        let before = TrackCode.encode(game.editorLayout!)
        XCTAssertFalse(game.editorCanUndo, "a fresh track has nothing to undo")

        XCTAssertTrue(game.editorAppend(Catalog.shortStraight))
        XCTAssertTrue(game.editorCanUndo)
        XCTAssertNotEqual(TrackCode.encode(game.editorLayout!), before)

        game.editorUndo()
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), before)
        XCTAssertFalse(game.editorCanUndo, "the stack is empty again")
    }

    /// A long history, walked all the way back. The plan's whole argument for depth
    /// is that snapshots are tiny, so this is the case that has to work.
    func testALongHistoryUndoesAllTheWayBack() {
        let game = editing()
        let start = TrackCode.encode(game.editorLayout!)
        var codes: [String] = [start]

        for _ in 0..<20 {
            guard game.editorAppend(Catalog.shortStraight) else { break }
            codes.append(TrackCode.encode(game.editorLayout!))
        }
        XCTAssertGreaterThan(codes.count, 5, "need a real history to walk back")

        // Undo back down the stack, checking each step lands on the code it made.
        for expected in codes.dropLast().reversed() {
            game.editorUndo()
            XCTAssertEqual(TrackCode.encode(game.editorLayout!), expected)
        }
        XCTAssertFalse(game.editorCanUndo)
    }

    /// Redo replays forward, and a fresh edit after undoing **discards** the redo
    /// tail — the standard contract, and the one that avoids a branching history
    /// nobody asked for.
    func testRedoReplaysAndANewEditDiscardsIt() {
        let game = editing()
        XCTAssertTrue(game.editorAppend(Catalog.shortStraight))
        let afterFirst = TrackCode.encode(game.editorLayout!)
        XCTAssertTrue(game.editorAppend(Catalog.longStraight))
        let afterSecond = TrackCode.encode(game.editorLayout!)

        game.editorUndo()
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), afterFirst)
        XCTAssertTrue(game.editorCanRedo)

        game.editorRedo()
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), afterSecond)

        // Undo, then edit: the redo tail is gone.
        game.editorUndo()
        XCTAssertTrue(game.editorCanRedo)
        XCTAssertTrue(game.editorAppend(Catalog.curve45MediumLeft))
        XCTAssertFalse(game.editorCanRedo, "a new edit must discard the redo tail")
    }

    /// A spent undo must be inert: no snapshot pushed, and the redo tail intact.
    /// The guard has to sit before either stack is touched.
    func testTappingUndoWithNothingToUndoLeavesRedoIntact() {
        let game = editing()
        XCTAssertTrue(game.editorAppend(Catalog.shortStraight))
        let edited = TrackCode.encode(game.editorLayout!)

        game.editorUndo()
        let rewound = TrackCode.encode(game.editorLayout!)
        XCTAssertFalse(game.editorCanUndo)
        XCTAssertTrue(game.editorCanRedo)

        // Hammer the spent undo. Nothing may move, and redo must survive.
        for _ in 0..<3 { game.editorUndo() }
        XCTAssertFalse(game.editorCanUndo, "a dead undo pushed its own snapshot")
        XCTAssertTrue(game.editorCanRedo, "a dead undo cleared the redo tail")
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), rewound, "the track moved")

        // And redo still gets the edit back.
        game.editorRedo()
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), edited)
    }

    /// Rotating after undoing discards the redo tail, and should: a new edit ends
    /// the branch. Rotate never refuses, so it's the likeliest case.
    func testAWholeTrackEditAfterUndoingDiscardsRedo() {
        let game = editing()
        for _ in 0..<3 { XCTAssertTrue(game.editorAppend(Catalog.shortStraight)) }
        game.editorUndo()
        game.editorUndo()
        XCTAssertTrue(game.editorCanRedo)

        XCTAssertTrue(game.editorRotate(eighths: 1), "rotate does not refuse on real tracks")
        XCTAssertFalse(game.editorCanRedo, "a real edit must discard the redo tail")
        // And it is itself undoable, so the author is not stranded.
        XCTAssertTrue(game.editorCanUndo)
    }

    /// The mirror case: a spent redo must be just as inert.
    func testTappingRedoWithNothingToRedoLeavesUndoIntact() {
        let game = editing()
        XCTAssertTrue(game.editorAppend(Catalog.shortStraight))
        let edited = TrackCode.encode(game.editorLayout!)

        for _ in 0..<3 { game.editorRedo() }
        XCTAssertTrue(game.editorCanUndo, "a dead redo ate the undo history")
        XCTAssertFalse(game.editorCanRedo)
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), edited, "the track moved")
    }

    /// **Undo is not itself an edit.** Restoring must not push a snapshot, or undo
    /// would only ever toggle between the last two states.
    func testUndoingDoesNotPushItsOwnSnapshot() {
        let game = editing()
        XCTAssertTrue(game.editorAppend(Catalog.shortStraight))
        XCTAssertTrue(game.editorAppend(Catalog.longStraight))
        let first = TrackCode.encode(game.editorLayout!)

        game.editorUndo()
        game.editorUndo()
        // Two undos from two edits must reach the original, not oscillate.
        XCTAssertNotEqual(TrackCode.encode(game.editorLayout!), first)
        XCTAssertFalse(game.editorCanUndo)
    }

    /// **A refused edit leaves no snapshot.** Otherwise tapping a grayed-out piece
    /// would silently fill the history with no-ops, and undo would appear broken.
    func testARefusedEditDoesNotTouchTheHistory() {
        let game = editing()
        XCTAssertTrue(game.editorAppend(Catalog.shortStraight))
        let code = TrackCode.encode(game.editorLayout!)

        // A fitter cannot be prepended (nothing to invert) — a genuine refusal.
        XCTAssertFalse(game.editorPrepend(PieceCatalog.fitterPieceID))
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), code)

        // One undo still reaches the state before the ONE real edit.
        game.editorUndo()
        XCTAssertNotEqual(TrackCode.encode(game.editorLayout!), code)
        XCTAssertFalse(game.editorCanUndo, "the refusal must not have added a step")
    }

    /// Whole-track operations are undoable too: rotate is offered as "try it and
    /// see", so it needs a one-tap way back.
    func testWholeTrackOperationsAreUndoable() {
        let game = editing()
        XCTAssertTrue(game.editorAppend(Catalog.shortStraight))
        let before = TrackCode.encode(game.editorLayout!)

        XCTAssertTrue(game.editorRotate(eighths: 2))
        XCTAssertNotEqual(TrackCode.encode(game.editorLayout!), before)
        game.editorUndo()
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), before, "rotate must be undoable")

        XCTAssertTrue(game.editorShiftHeight(steps: 1))
        game.editorUndo()
        XCTAssertEqual(
            TrackCode.encode(game.editorLayout!), before, "height shift must be undoable")

        game.editorToggleGate(seam: 1)
        game.editorUndo()
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), before, "gating must be undoable")
    }

    /// A one-tap compound is one undo step, not one per primitive — the tap was
    /// one act of intent, and that is what the author expects back.
    func testACompoundIsOneUndoStep() {
        let game = editing()
        let before = TrackCode.encode(game.editorLayout!)
        let compound = Catalog.jog240Right
        XCTAssertGreaterThan(
            PieceExpansion.expand(compound, mode: .flat).count, 1, "fixture must be compound")

        XCTAssertTrue(game.editorAppend(compound))
        game.editorUndo()
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), before)
    }

    /// Starting a fresh track clears the history: undoing across a reset would
    /// resurrect a track the author deliberately threw away.
    func testResetClearsTheHistory() {
        let game = editing()
        XCTAssertTrue(game.editorAppend(Catalog.shortStraight))
        game.editorReset()
        XCTAssertFalse(game.editorCanUndo)
        XCTAssertFalse(game.editorCanRedo)
    }

    /// The history is bounded, and it drops from the BOTTOM — the oldest states go,
    /// the recent ones (the ones anybody undoes to) stay.
    ///
    /// Driven by toggling a gate rather than adding pieces: the canvas refuses more
    /// straights after about ten, which is nowhere near the cap. Toggling is
    /// always available and is a real recorded edit, so it fills the stack.
    func testTheHistoryIsBoundedAndDropsTheOldest() {
        let game = editing()
        XCTAssertTrue(game.editorAppend(Catalog.shortStraight))
        let cap = CouchGame.undoDepth

        // One more than the cap, so the oldest must have been dropped.
        for _ in 0..<(cap + 10) { game.editorToggleGate(seam: 1) }

        var steps = 0
        while game.editorCanUndo {
            game.editorUndo()
            steps += 1
            XCTAssertLessThanOrEqual(steps, cap, "the stack outgrew its cap")
        }
        XCTAssertEqual(steps, cap, "the stack should be full, not short")
    }
}
