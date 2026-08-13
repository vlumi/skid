import Foundation
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Opening one of your tracks to edit — and what must not happen when you do.**
///
/// The library has stored many tracks since v0.6.0 while the editor had one buffer, so
/// this is the missing direction: edits flowed *to* the library, nothing flowed back.
///
/// The subtle part is that editing is safe in place, and for a non-obvious reason: an
/// entry's id is a hash of its own content, so an edit necessarily writes a *different*
/// row and drops the one it came from, carrying the name across. Editing therefore MOVES a
/// track. Several of these tests exist to pin that it moves rather than duplicating or
/// stranding.
@MainActor
final class OpenTrackTests: XCTestCase {
    /// A game whose library starts genuinely empty.
    ///
    /// **The legacy custom slot lives in `UserDefaults`**, which is process-wide, and
    /// `migratedLibrary` folds it into any empty book on launch — so a "fresh" game already
    /// held a "My track" row, and every count assertion here was off by one. Clearing the
    /// book after construction is what makes these tests about the code under test rather
    /// than about whatever an earlier test left in defaults.
    private func game() -> CouchGame {
        let game = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-open-\(UUID().uuidString).json",
            profileFilename: "test-open-\(UUID().uuidString).json")
        game.library = TrackLibraryBook()
        game.editedEntryID = nil
        return game
    }

    /// Put a real track in the library and return its entry.
    private func seed(_ game: CouchGame, name: String = "Mine") -> TrackLibraryBook.Entry {
        let code = TrackLibrary.builtins[0].code
        var book = game.library
        let entry = TrackLibraryBook.Entry(
            name: name, code: code, isRaceable: true, createdAt: Date(), updatedAt: Date())
        book.put(entry)
        game.library = book
        return entry
    }

    /// **The gap this closes**: an entry loads into the editor.
    func testAnEntryOpensInTheEditor() throws {
        let game = self.game()
        let entry = seed(game)
        XCTAssertTrue(game.openForEditing(entryID: entry.id))
        let layout = try XCTUnwrap(game.editorLayout)
        XCTAssertEqual(TrackCode.encode(layout), entry.code, "a different track was loaded")
        XCTAssertEqual(game.editedEntryID, entry.id, "the editor is not tracking that row")
    }

    /// An id that is not in the book is refused rather than clearing the canvas.
    func testAnUnknownEntryIsRefused() {
        let game = self.game()
        game.newTrackForEditing()
        let before = game.editorLayout
        XCTAssertFalse(game.openForEditing(entryID: "no-such-entry"))
        XCTAssertEqual(game.editorLayout, before, "a failed open disturbed the canvas")
    }

    /// **Editing moves the row rather than leaving a stray behind.**
    ///
    /// Sabotage: drop the `previous` lookup in `syncEditedTrackToLibrary` so the old row is
    /// never removed — two tracks where the author has one, and the name lost.
    ///
    /// (Swapping the assignment order in `openForEditing` does *not* break this, which was
    /// worth checking: the loaded code is already in the book, so the sync's own
    /// `contains(code:)` guard returns first either way.)
    func testEditingAnOpenedTrackDoesNotLeaveTheOriginalBehind() throws {
        let game = self.game()
        let entry = seed(game, name: "Kept")
        XCTAssertEqual(game.library.tracks.count, 1)

        XCTAssertTrue(game.openForEditing(entryID: entry.id))
        // Any real edit: append a piece.
        var layout = try XCTUnwrap(game.editorLayout)
        layout.pieces.append(PieceCatalog.ID.straight)
        game.editorLayout = layout

        XCTAssertEqual(game.library.tracks.count, 1, "editing left the original behind")
        XCTAssertEqual(game.library.tracks.first?.name, "Kept", "the name was lost")
        XCTAssertNil(game.library.entry(id: entry.id), "the old row survived its own edit")
    }

    /// **Starting a copy claims no row**, so the original survives the first edit.
    ///
    /// A stored copy is impossible by construction: an entry's id is a hash of its content,
    /// so writing a second row with the same code would REPLACE the original rather than
    /// sit beside it. Claiming nothing and letting the first edit write a fresh row is the
    /// version that works — and it means an unedited copy leaves no trace, which is honest
    /// rather than missing.
    func testStartingACopyKeepsTheOriginal() throws {
        let game = self.game()
        let entry = seed(game, name: "Original")
        XCTAssertTrue(game.startFrom(code: entry.code, name: entry.name))
        XCTAssertNil(game.editedEntryID, "the copy claimed the original's row")
        XCTAssertEqual(game.library.tracks.count, 1, "an unedited copy was stored")

        // The first edit writes the copy, and the original is still there.
        var layout = try XCTUnwrap(game.editorLayout)
        layout.pieces.append(PieceCatalog.ID.straight)
        game.editorLayout = layout

        XCTAssertEqual(game.library.tracks.count, 2)
        XCTAssertNotNil(game.library.entry(id: entry.id), "the original was consumed")
        let names = Set(game.library.tracks.map(\.name))
        XCTAssertTrue(names.contains("Original"))
        XCTAssertTrue(names.contains("Original 2"), "the copy is not named as one: \(names)")
    }

    /// Copies number upward rather than nesting "copy of copy of".
    func testCopyNamesCount() {
        let game = self.game()
        XCTAssertEqual(game.duplicateName(of: "Ring"), "Ring 2")
        _ = seed(game, name: "Ring 2")
        XCTAssertEqual(game.duplicateName(of: "Ring 2"), "Ring 3")
        XCTAssertEqual(game.duplicateName(of: "Ring"), "Ring 3", "walked onto a taken name")
    }

    /// A built-in loads for editing without being stored — it ships in the binary and has
    /// no row to claim, so only the eventual EDIT becomes a track of yours.
    func testABuiltinLoadsWithoutBeingStored() throws {
        let game = self.game()
        let builtin = TrackLibrary.builtins[1]
        XCTAssertTrue(
            game.startFrom(
                code: builtin.code, name: TrackLibrary.displayName(id: builtin.id)))
        XCTAssertTrue(game.library.tracks.isEmpty, "opening a built-in stored a copy")
        let layout = try XCTUnwrap(game.editorLayout)
        XCTAssertEqual(TrackCode.encode(layout), builtin.code)
    }

    /// A new track starts from one piece and belongs to no row yet.
    func testANewTrackTracksNoEntry() throws {
        let game = self.game()
        let entry = seed(game)
        XCTAssertTrue(game.openForEditing(entryID: entry.id))
        game.newTrackForEditing()
        XCTAssertNil(game.editedEntryID, "a new track is still editing the old row")
        XCTAssertEqual(game.editorLayout?.pieces.count, 1)
    }

    /// **Deleting the track being edited must clear the tracked row**, or the next edit
    /// tries to replace a row that is gone and quietly resurrects it.
    func testDeletingTheEditedTrackStopsTrackingIt() throws {
        let game = self.game()
        let entry = seed(game)
        XCTAssertTrue(game.openForEditing(entryID: entry.id))
        game.deleteTrack(id: entry.id)
        XCTAssertNil(game.editedEntryID)
        XCTAssertTrue(game.library.tracks.isEmpty)

        // …and an edit afterwards starts a fresh row rather than restoring the deleted one.
        var layout = try XCTUnwrap(game.editorLayout)
        layout.pieces.append(PieceCatalog.ID.straight)
        game.editorLayout = layout
        XCTAssertEqual(game.library.tracks.count, 1)
        XCTAssertNil(game.library.entry(id: entry.id), "the deleted row came back")
    }

    /// Deleting the SELECTED race track falls back to a built-in, rather than leaving the
    /// picker showing a name that is gone (which `selectedTrack()` would silently
    /// substitute for anyway).
    func testDeletingTheSelectedTrackFallsBack() {
        let game = self.game()
        let entry = seed(game)
        game.trackID = entry.trackID
        game.deleteTrack(id: entry.id)
        XCTAssertEqual(game.trackID, TrackLibrary.builtins[0].id)
        XCTAssertNotNil(TrackLibrary.builtin(id: game.trackID))
    }

    /// Deleting something else leaves both the selection and the edited row alone.
    func testDeletingAnotherTrackDisturbsNothing() {
        let game = self.game()
        let mine = seed(game, name: "Mine")
        game.trackID = mine.trackID
        game.deleteTrack(id: "no-such-entry")
        XCTAssertEqual(game.trackID, mine.trackID)
        XCTAssertEqual(game.library.tracks.count, 1)
    }

    /// The editor opens on the shelf when there are tracks to choose from, and straight
    /// onto the canvas when there are none — nobody should be asked to pick from an empty
    /// list.
    func testTheShelfOpensOnlyWhenThereIsSomethingOnIt() {
        let empty = self.game()
        empty.openEditor()
        XCTAssertFalse(empty.showingTrackShelf)

        let stocked = self.game()
        _ = seed(stocked)
        stocked.openEditor()
        XCTAssertTrue(stocked.showingTrackShelf)
    }
}

/// **Renaming a track** — the one edit that changes a row without changing the road.
@MainActor
final class RenameTrackTests: XCTestCase {
    private func game() -> CouchGame {
        let game = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-rename-\(UUID().uuidString).json",
            profileFilename: "test-rename-\(UUID().uuidString).json")
        // See OpenTrackTests: the legacy slot lives in process-wide UserDefaults and the
        // migration folds it into any empty book, so a "fresh" game already has a row.
        game.library = TrackLibraryBook()
        game.editedEntryID = nil
        return game
    }

    private func seed(_ game: CouchGame, name: String = "Mine") -> TrackLibraryBook.Entry {
        var book = game.library
        let entry = TrackLibraryBook.Entry(
            name: name, code: TrackLibrary.builtins[0].code, isRaceable: true,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000))
        book.put(entry)
        game.library = book
        return entry
    }

    func testRenamingChangesTheName() {
        let game = self.game()
        let entry = seed(game, name: "Old")
        XCTAssertTrue(game.renameTrack(id: entry.id, to: "New"))
        XCTAssertEqual(game.library.entry(id: entry.id)?.name, "New")
        XCTAssertEqual(game.library.tracks.count, 1, "renaming made a second row")
    }

    /// **The id does not move.** It is a hash of the track's content, and a name is not
    /// content — so a rename must not orphan the row's records or its place in the shelf.
    func testRenamingKeepsTheIdentity() {
        let game = self.game()
        let entry = seed(game, name: "Old")
        game.renameTrack(id: entry.id, to: "New")
        XCTAssertNotNil(game.library.entry(id: entry.id))
        XCTAssertEqual(game.library.tracks.first?.id, entry.id)
        XCTAssertEqual(game.library.tracks.first?.code, entry.code, "the road changed")
    }

    /// **`updatedAt` is not touched**, because it means "last edited here" and orders the
    /// shelf — renaming would push a track you have not driven to the front.
    func testRenamingDoesNotReorderTheShelf() {
        let game = self.game()
        let old = seed(game, name: "Old")
        var book = game.library
        book.put(
            TrackLibraryBook.Entry(
                name: "Newer", code: TrackLibrary.builtins[1].code, isRaceable: true,
                createdAt: Date(timeIntervalSince1970: 9_000),
                updatedAt: Date(timeIntervalSince1970: 9_000)))
        game.library = book
        XCTAssertEqual(game.library.byRecency.first?.name, "Newer")

        game.renameTrack(id: old.id, to: "Renamed")
        XCTAssertEqual(
            game.library.byRecency.first?.name, "Newer",
            "renaming jumped the track to the front of the shelf")
    }

    /// An unusable name keeps the old one: a track called "" is worse than "My track".
    func testAnEmptyNameIsRefused() {
        let game = self.game()
        let entry = seed(game, name: "Keep")
        XCTAssertFalse(game.renameTrack(id: entry.id, to: "   "))
        XCTAssertEqual(game.library.entry(id: entry.id)?.name, "Keep")
    }

    /// Names are trimmed and capped rather than refused, so a paste does not fail.
    func testNamesAreTrimmedAndCapped() {
        let game = self.game()
        let entry = seed(game)
        game.renameTrack(id: entry.id, to: "  Spaced  ")
        XCTAssertEqual(game.library.entry(id: entry.id)?.name, "Spaced")

        game.renameTrack(id: entry.id, to: String(repeating: "x", count: 200))
        XCTAssertEqual(game.library.entry(id: entry.id)?.name.count, TrackName.maxLength)
    }

    /// Renaming something that is not there does nothing, rather than inventing a row.
    func testRenamingAnUnknownTrackDoesNothing() {
        let game = self.game()
        XCTAssertFalse(game.renameTrack(id: "no-such-track", to: "Whatever"))
        XCTAssertTrue(game.library.tracks.isEmpty)
    }

    /// Renaming to the same name succeeds and is a no-op — a caller should not have to
    /// check first, and it must not rewrite the row for nothing.
    func testRenamingToTheSameNameIsHarmless() {
        let game = self.game()
        let entry = seed(game, name: "Same")
        XCTAssertTrue(game.renameTrack(id: entry.id, to: "Same"))
        XCTAssertEqual(game.library.entry(id: entry.id)?.name, "Same")
        XCTAssertEqual(game.library.tracks.count, 1)
    }

    /// Two tracks may share a name. The id keeps them apart, and refusing would be worse
    /// than the ambiguity — the same call the profile book makes.
    func testTwoTracksMayShareAName() {
        let game = self.game()
        let first = seed(game, name: "Ring")
        var book = game.library
        let second = TrackLibraryBook.Entry(
            name: "Other", code: TrackLibrary.builtins[1].code, isRaceable: true,
            createdAt: Date(), updatedAt: Date())
        book.put(second)
        game.library = book

        XCTAssertTrue(game.renameTrack(id: second.id, to: "Ring"))
        XCTAssertEqual(game.library.tracks.count, 2)
        XCTAssertEqual(game.library.entry(id: first.id)?.name, "Ring")
        XCTAssertEqual(game.library.entry(id: second.id)?.name, "Ring")
    }
}
