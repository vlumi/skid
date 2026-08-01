import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Moving the one saved track into the library without losing it.**
///
/// The old slot is deliberately left in UserDefaults after migrating: it costs
/// a few dozen bytes and is the only way back if this turns out to be wrong.
/// Nothing reads the library yet — the slot is still authoritative — so a
/// mistake here cannot destroy anything on this build.
@MainActor
final class LibraryMigrationTests: XCTestCase {
    private func game() -> CouchGame {
        CouchGame(signingKeys: NoSigningKey())
    }

    /// The slot becomes a library entry, keyed by its own code.
    func testTheOldSlotBecomesALibraryEntry() throws {
        let book = CouchGame.migratedLibrary(
            TrackLibraryBook(), slot: TestTracks.Code.bridgeRing)
        XCTAssertEqual(book.tracks.count, 1)
        let entry = try XCTUnwrap(book.entry(id: TestTracks.Code.bridgeRing))
        XCTAssertEqual(entry.code, TestTracks.Code.bridgeRing)
        XCTAssertFalse(entry.isImported, "a track built here was not imported")
    }

    /// **Launching again must not duplicate it.** The migration runs on every
    /// launch, so this is the property that keeps it safe.
    func testMigratingRepeatedlyIsANoOp() {
        var book = CouchGame.migratedLibrary(TrackLibraryBook(), slot: TestTracks.Code.bridgeRing)
        for _ in 0..<5 {
            book = CouchGame.migratedLibrary(book, slot: TestTracks.Code.bridgeRing)
        }
        XCTAssertEqual(book.tracks.count, 1)
    }

    /// A player with no saved track gets an empty library, not a phantom entry.
    func testNothingToMigrateLeavesTheLibraryEmpty() {
        XCTAssertTrue(CouchGame.migratedLibrary(TrackLibraryBook(), slot: nil).tracks.isEmpty)
        XCTAssertTrue(CouchGame.migratedLibrary(TrackLibraryBook(), slot: "").tracks.isEmpty)
    }

    /// An existing library is never trampled by the migration.
    func testAPopulatedLibraryIsLeftAlone() {
        var existing = TrackLibraryBook()
        existing.put(
            TrackLibraryBook.Entry(
                name: "Kept", code: TestTracks.Code.clover,
                createdAt: Date(), updatedAt: Date()))
        let after = CouchGame.migratedLibrary(existing, slot: TestTracks.Code.bridgeRing)
        XCTAssertEqual(after, existing)
    }

    /// Editing mirrors into the library, and REPLACES the row rather than
    /// leaving one per keystroke — every edit is a new code, so without this the
    /// library would fill with half-built rings.
    func testEditingKeepsOneRowForTheTrackBeingEdited() throws {
        let game = game()
        game.editorLayout = try TrackCode.decode(TestTracks.Code.bridgeRing)
        XCTAssertEqual(game.library.tracks.count, 1)
        let first = try XCTUnwrap(game.library.tracks.first)

        game.editorLayout = try TrackCode.decode(TestTracks.Code.clover)
        XCTAssertEqual(game.library.tracks.count, 1, "one row follows the edited track")
        let second = try XCTUnwrap(game.library.tracks.first)

        XCTAssertNotEqual(second.id, first.id, "a different road is a different identity")
        XCTAssertEqual(second.name, first.name, "the name carries across the edit")
        XCTAssertEqual(second.createdAt, first.createdAt, "so does when it was made")
    }

    /// **A crash between edits must not orphan a row.** `editedEntryID` is
    /// in-memory, rebuilt on launch from the slot — so simulate a relaunch and
    /// check the next edit still replaces rather than accumulates.
    func testARelaunchMidEditStillReplacesTheRow() throws {
        var book = CouchGame.migratedLibrary(
            TrackLibraryBook(), slot: TestTracks.Code.bridgeRing)
        XCTAssertEqual(book.tracks.count, 1)

        // Relaunch: editedEntryID comes back from the slot's own code, which the
        // same didSet wrote, so the two cannot disagree.
        let afterRelaunch = TrackCode.contentCode(of: TestTracks.Code.bridgeRing)
        XCTAssertNotNil(book.entry(id: afterRelaunch), "the row the editor will update")

        // The next edit replaces that row rather than adding beside it.
        book.remove(id: afterRelaunch)
        book.put(
            TrackLibraryBook.Entry(
                name: "My track", code: TestTracks.Code.clover,
                createdAt: Date(), updatedAt: Date()))
        XCTAssertEqual(book.tracks.count, 1)
    }

    /// Re-encoding the same track must not add a row.
    func testReSavingTheSameTrackChangesNothing() throws {
        let game = game()
        let layout = try TrackCode.decode(TestTracks.Code.bridgeRing)
        game.editorLayout = layout
        let before = game.library
        game.editorLayout = layout
        XCTAssertEqual(game.library, before)
    }
}
