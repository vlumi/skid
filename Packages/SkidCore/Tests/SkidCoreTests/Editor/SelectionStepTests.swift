import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Stepping the selection along the ring.**
///
/// Exists for bulk property edits — rail this run, mark those corners — where re-aiming
/// a tap at each piece was the cost. The step must wrap at both ends and go nowhere
/// when nothing is selected.
@MainActor
final class SelectionStepTests: XCTestCase {
    private func game(pieces: Int = 4) -> CouchGame {
        let unique = UUID().uuidString
        let game = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-lib-\(unique).json",
            profileFilename: "test-profiles-\(unique).json",
            hiscoreFilename: "test-hiscores-\(unique).json")
        game.editorLayout = TrackLayout(
            pieces: [PieceCatalog.startPieceID] + Array(repeating: 1, count: pieces - 1))
        return game
    }

    override func tearDown() {
        super.tearDown()
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Skid", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasPrefix("test-") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// Forward and back move by one.
    func testStepsMoveByOne() {
        let game = self.game()
        game.editorSelect(1)
        game.editorStepSelection(1)
        XCTAssertEqual(game.editorSelectedPiece, 2)
        game.editorStepSelection(-1)
        XCTAssertEqual(game.editorSelectedPiece, 1)
    }

    /// **The ring wraps**: forward off the end lands on piece 0, back off the start
    /// lands on the last — a ring has no ends to stop at.
    func testSteppingWrapsAroundTheRing() {
        let game = self.game(pieces: 4)
        game.editorSelect(3)
        game.editorStepSelection(1)
        XCTAssertEqual(game.editorSelectedPiece, 0, "forward off the end should wrap to 0")
        game.editorStepSelection(-1)
        XCTAssertEqual(game.editorSelectedPiece, 3, "back off the start should wrap to the last")
    }

    /// With nothing selected, a step has no anchor and does nothing — it must not
    /// invent a selection.
    func testSteppingFromNothingDoesNothing() {
        let game = self.game()
        game.editorSelect(nil)
        game.editorStepSelection(1)
        XCTAssertNil(game.editorSelectedPiece)
    }
}
