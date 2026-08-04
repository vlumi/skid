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

    /// A SHORT open chain, so append and prepend both actually run.
    ///
    /// Neither shipped fixture works here: a closed ring refuses prepend, and the
    /// 46-piece `cloverOpen` is so near closure it refuses everything. Both refusals
    /// are silent, which is what made the first version of these tests pass while
    /// covering nothing — hence the explicit assertions that a piece was laid.
    private func openChain() -> CouchGame {
        let game = CouchGame()
        game.editorLayout = TrackLayout(
            pieces: [PieceCatalog.startPieceID, PieceCatalog.ID.straight], gateSeams: [0])
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

    // MARK: - Railing pieces as they are laid

    /// **The sticky toggle rails what you build next**, so railing a bridge is one
    /// decision rather than one tap per piece.
    func testAppendRailsTheNewPieces() throws {
        let game = openChain()
        game.editorRailNewPieces = true
        let before = game.editorLayout!.pieces.count
        XCTAssertTrue(
            game.editorAppend(PieceCatalog.ID.straight), "an open chain must accept a piece")
        let layout = game.editorLayout!
        XCTAssertGreaterThan(layout.pieces.count, before, "something was actually laid")
        for index in before..<layout.pieces.count {
            XCTAssertTrue(
                layout.isRailed(at: index), "piece \(index) was laid with the toggle on")
        }
    }

    /// And leaves them bare when it is off — the default.
    func testAppendLeavesThePiecesBareWhenTheToggleIsOff() throws {
        let game = openChain()
        game.editorRailNewPieces = false
        let before = game.editorLayout!.pieces.count
        XCTAssertTrue(game.editorAppend(PieceCatalog.ID.straight))
        let layout = game.editorLayout!
        XCTAssertGreaterThan(layout.pieces.count, before)
        for index in before..<layout.pieces.count {
            XCTAssertFalse(layout.isRailed(at: index), "the toggle was off")
        }
    }

    /// **Prepend rails the LEADING pieces**, and the rails already on the track
    /// shift with their pieces — the index arithmetic is the opposite of append's,
    /// which is why the two paths are written separately.
    func testPrependRailsTheNewPiecesAndShiftsTheOldOnes() throws {
        let game = openChain()
        var layout = game.editorLayout!
        layout.railed = [1]
        game.editorLayout = layout
        game.clearUndoHistory()
        game.editorRailNewPieces = true

        let before = game.editorLayout!.pieces.count
        XCTAssertTrue(
            game.editorPrepend(PieceCatalog.ID.straight), "an open chain must accept a head piece")
        let after = game.editorLayout!
        let added = after.pieces.count - before
        XCTAssertGreaterThan(added, 0, "something was actually laid")
        for index in 0..<added {
            XCTAssertTrue(after.isRailed(at: index), "the new leading piece must be railed")
        }
        XCTAssertTrue(
            after.isRailed(at: 1 + added),
            "and the railing already on the track must follow its own piece")
    }

    /// An index that names no piece is refused rather than stored — otherwise a
    /// stale selection could rail a piece that does not exist.
    func testAnIndexPastThePiecesIsRefused() throws {
        let game = try ring()
        XCTAssertFalse(game.editorToggleRail(at: 999))
        XCTAssertFalse(game.editorIsRailed(at: 999))
    }
}
