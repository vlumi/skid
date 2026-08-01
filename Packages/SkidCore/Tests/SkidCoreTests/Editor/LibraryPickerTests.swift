import XCTest

@testable import SkidCore
@testable import SkidKit

/// Racing from the library instead of the one custom slot.
@MainActor
final class LibraryPickerTests: XCTestCase {
    private func game() -> CouchGame {
        CouchGame(signingKeys: NoSigningKey(), libraryFilename: "test-\(UUID()).json")
    }

    /// `CouchGame()` reads the REAL UserDefaults, so a slot left by another test
    /// migrates into the library at init and the counts here become whatever ran
    /// first. Same hazard `TuningWireTests` documents for `@AppStorage`.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "skid.editor.customTrack")
    }

    private var ring: TrackLayout {
        // swiftlint:disable:next force_try
        try! TrackCode.decode(TestTracks.Code.bridgeRing)
    }

    /// An edited track becomes a raceable choice, and racing it compiles under
    /// the entry's own id so hiscores attach to that road.
    func testAnEditedTrackIsRaceableUnderItsOwnID() throws {
        let game = game()
        game.editorLayout = ring

        let entry = try XCTUnwrap(game.library.raceable.first)
        XCTAssertEqual(entry.trackID, TestTracks.Code.bridgeRing)

        game.trackID = entry.trackID
        XCTAssertEqual(game.selectedTrack().id, entry.trackID)
    }

    /// **An unfinished ring is not a choice.** The picker lists only raceable
    /// entries, so a draft never appears as something to start a race on.
    func testAnUnfinishedTrackIsNotOffered() {
        let game = game()
        game.editorReset()
        for _ in 0..<3 { _ = game.editorAppend(PieceCatalog.ID.shortStraight) }

        XCTAssertFalse(game.library.tracks.isEmpty, "the draft is still SAVED")
        XCTAssertTrue(game.library.raceable.isEmpty, "but not offered to race")
    }

    /// **Raceability is read, not recompiled.** A stale flag must be believed —
    /// otherwise the picker is compiling per render again.
    func testRaceabilityComesFromTheEntry() {
        var book = TrackLibraryBook()
        book.put(
            TrackLibraryBook.Entry(
                name: "Claims to be raceable", code: TestTracks.Code.cloverOpen,
                isRaceable: true, createdAt: Date(), updatedAt: Date()))
        XCTAssertEqual(book.raceable.count, 1)
    }

    /// Built-ins still resolve, and still win over a library row.
    func testBuiltinsStillRace() {
        let game = game()
        for builtin in TrackLibrary.builtins {
            game.trackID = builtin.id
            XCTAssertEqual(game.selectedTrack().id, builtin.id)
        }
    }

    /// A track id that no longer exists falls back rather than refusing to
    /// start — a picker aimed at a deleted track must still race something.
    func testADeletedTrackFallsBack() {
        let game = game()
        game.trackID = "not-a-track"
        XCTAssertEqual(game.selectedTrack().id, TrackLibrary.all[0].id)
    }

    // MARK: - Import

    func testPastingFilesTheTrackInTheLibrary() throws {
        let game = game()
        XCTAssertTrue(game.loadCustomTrack(code: TestTracks.Code.clover))

        let entry = try XCTUnwrap(game.library.entry(id: TestTracks.Code.clover))
        XCTAssertTrue(entry.isImported)
        XCTAssertTrue(entry.isRaceable)
        XCTAssertNil(entry.authorKey)
    }

    /// A signed import keeps the SIGNED code, so it can be passed on intact,
    /// and records who signed it.
    func testASignedImportKeepsItsSignature() throws {
        let game = game()
        let key = InMemorySigningKey()
        let signed = try TrackCode.encode(ring, signedBy: key)
        XCTAssertTrue(game.loadCustomTrack(code: signed))

        let entry = try XCTUnwrap(game.library.entry(id: TestTracks.Code.bridgeRing))
        XCTAssertEqual(entry.code, signed, "the signed bytes are kept for re-sharing")
        XCTAssertEqual(entry.authorKey, key.publicKey)
        XCTAssertTrue(entry.signatureIsValid)
    }

    /// **Re-importing keeps the name you gave it.** Arriving again is not a
    /// reason to rename someone's track back to "Imported track".
    func testReimportingDoesNotRename() throws {
        let game = game()
        XCTAssertTrue(game.loadCustomTrack(code: TestTracks.Code.clover))
        var book = game.library
        var renamed = try XCTUnwrap(book.entry(id: TestTracks.Code.clover))
        renamed.name = "Clover, my beloved"
        book.put(renamed)
        game.library = book

        XCTAssertTrue(game.loadCustomTrack(code: TestTracks.Code.clover))
        XCTAssertEqual(game.library.tracks.count, 1)
        XCTAssertEqual(game.library.entry(id: TestTracks.Code.clover)?.name, "Clover, my beloved")
    }

    /// Editing an imported track replaces its row rather than leaving the
    /// import behind as a stray.
    ///
    /// Edited by APPENDING to what was imported, not by swapping in an
    /// unrelated track — a different road is legitimately a different entry, so
    /// that would prove nothing.
    func testEditingAnImportReplacesItsRow() throws {
        let game = game()
        // A SHORT open chain, so there is room to append. `cloverOpen` is 46
        // pieces with one end and no room left — every append is refused.
        let short = TrackCode.encode(
            TrackLayout(pieces: [PieceCatalog.startPieceID], gateSeams: [0]))
        XCTAssertTrue(game.loadCustomTrack(code: short))
        XCTAssertEqual(game.library.tracks.count, 1)
        let imported = try XCTUnwrap(game.library.tracks.first)

        // Extend the imported chain: same lineage, a new road.
        XCTAssertTrue(game.editorAppend(PieceCatalog.ID.shortStraight))

        XCTAssertEqual(game.library.tracks.count, 1, "the row follows the edit")
        let after = try XCTUnwrap(game.library.tracks.first)
        XCTAssertNotEqual(after.id, imported.id, "a different road, so a new identity")
        XCTAssertEqual(after.name, imported.name, "but it keeps the name")
        XCTAssertEqual(after.importedAt, imported.importedAt, "and stays marked imported")
    }
}
