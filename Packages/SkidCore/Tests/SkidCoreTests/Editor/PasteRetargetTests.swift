import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Pasting a track means editing THAT track's row** — even when the library
/// already holds it. The retarget used to be skipped on the already-held path,
/// so the editor kept claiming its previous row: the next edit then replaced
/// that row, keeping the old row's name and deleting its track. Reported as "I
/// put a name on my custom track, but it now shows up as 'My track' again".
@MainActor
final class PasteRetargetTests: XCTestCase {
    private func game() -> CouchGame {
        let game = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-paste-\(UUID().uuidString).json",
            profileFilename: "test-paste-\(UUID().uuidString).json",
            setupFilename: "test-paste-\(UUID().uuidString).json")
        game.library = TrackLibraryBook()
        game.editedEntryID = nil
        return game
    }

    func testPastingAnExistingRowRetargetsTheEditor() throws {
        let game = self.game()
        // A named track in the library: paste it in fresh, then name it. An
        // OPEN layout, so edits can still append to it after each paste.
        let named = TrackCode.encode(
            TrackLayout(pieces: [
                PieceCatalog.startPieceID, PieceCatalog.ID.shortStraight,
                PieceCatalog.ID.shortStraight,
            ]))
        XCTAssertTrue(game.loadCustomTrack(code: named))
        let namedID = try XCTUnwrap(game.editedEntryID)
        XCTAssertTrue(game.renameTrack(id: namedID, to: "Knot"))

        // Work on something else, so the editor's claim moves off that row.
        game.newTrackForEditing()
        game.editorSelect(0)
        XCTAssertTrue(game.editorPlace(PieceCatalog.ID.shortStraight))
        let otherID = game.editedEntryID
        XCTAssertNotEqual(otherID, namedID)

        // Paste the NAMED track again — the library already holds it.
        XCTAssertTrue(game.loadCustomTrack(code: named))
        XCTAssertEqual(
            game.editedEntryID, namedID,
            "the editor still claims the previous row — the next edit would eat it")

        // And an edit follows the named row: same name, new code, other row intact.
        game.editorSelect(0)
        XCTAssertTrue(game.editorPlace(PieceCatalog.ID.shortStraight))
        let rows = game.library.tracks
        XCTAssertEqual(rows.filter { $0.name == "Knot" }.count, 1, "the name was lost")
        XCTAssertNotNil(
            game.editedEntryID.flatMap { id in rows.first { $0.id == id && $0.name == "Knot" } },
            "the edit did not stay on the named row")
        XCTAssertNotNil(
            rows.first { $0.id == otherID },
            "the other track was eaten by the edit")
    }
}
