import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Railings are toggled on a piece you have already laid**, like a decal —
/// so the editor gains a property on the selected piece rather than doubling
/// the palette with railed and unrailed variants of every shape.
@MainActor
final class RailToggleTests: XCTestCase {
    private func ring() throws -> CouchGame {
        let game = CouchGame()
        game.editorLayout = try TrackCode.decode(TestTracks.Code.bridgeRing)
        game.clearUndoHistory()
        return game
    }

    func testTogglingRailsAPiece() throws {
        let game = try ring()
        let before = game.editorIsRailed(at: 3)
        XCTAssertTrue(game.editorToggleRail(at: 3))
        XCTAssertNotEqual(game.editorIsRailed(at: 3), before, "the toggle must flip")
        XCTAssertTrue(game.editorToggleRail(at: 3))
        XCTAssertEqual(game.editorIsRailed(at: 3), before, "and flip back")
    }

    /// It is one edit, so one undo takes it back — the same contract as every
    /// other editor action.
    func testTogglingIsUndoable() throws {
        let game = try ring()
        let before = TrackCode.encode(game.editorLayout!)
        XCTAssertTrue(game.editorToggleRail(at: 3))
        XCTAssertNotEqual(TrackCode.encode(game.editorLayout!), before)
        game.editorUndo()
        XCTAssertEqual(
            TrackCode.encode(game.editorLayout!), before,
            "one undo must restore the railing state exactly")
    }

    /// **Geometry is untouched.** Railing is paint-like: the road, the seams and
    /// every index stay exactly as they were.
    func testTogglingDoesNotMoveTheRoad() throws {
        let game = try ring()
        let layout = game.editorLayout!
        XCTAssertTrue(game.editorToggleRail(at: 3))
        let after = game.editorLayout!
        XCTAssertEqual(after.pieces, layout.pieces)
        XCTAssertEqual(after.gateSeams, layout.gateSeams)
        XCTAssertEqual(after.pitches, layout.pitches)
        XCTAssertEqual(after.origin, layout.origin)
    }

    /// An index that names no piece is refused rather than stored — otherwise a
    /// stale selection could rail a piece that does not exist.
    func testAnIndexPastThePiecesIsRefused() throws {
        let game = try ring()
        XCTAssertFalse(game.editorToggleRail(at: 999))
        XCTAssertFalse(game.editorIsRailed(at: 999))
    }
}
