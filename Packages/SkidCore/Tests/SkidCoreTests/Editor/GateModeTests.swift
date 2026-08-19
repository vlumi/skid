import SkidCore
import XCTest

@testable import SkidKit

/// Gating as its own edit mode. One tap on the map meant two things — select an
/// end, or toggle a checkpoint — and a stray seam hit was a silent real edit.
/// (That's how a tap leaking through a disabled button went unnoticed.) Modes
/// separate them: seam taps only gate in gate mode, nothing else does.
@MainActor
final class GateModeTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    private func closedRing() throws -> CouchGame {
        let game = CouchGame(setupFilename: "test-\(UUID().uuidString).json")
        game.editorLayout = try TrackCode.decode(
            TestTracks.Code.bridgeRing)
        game.clearUndoHistory()
        return game
    }

    func testBuildModeIsTheDefault() throws {
        let game = try closedRing()
        XCTAssertEqual(game.editorMode, .build)
    }

    /// Outside gate mode, a seam tap must not gate — that's the conflict.
    func testASeamTapOnlyGatesInGateMode() throws {
        let game = try closedRing()
        let before = game.editorLayout!.gateSeams

        XCTAssertFalse(game.editorToggleGate(seam: 4), "build mode must not gate")
        XCTAssertEqual(game.editorLayout!.gateSeams, before)
        XCTAssertFalse(game.editorCanUndo, "a refused gate tap must not record")

        game.editorMode = .gate
        XCTAssertTrue(game.editorToggleGate(seam: 4))
        XCTAssertNotEqual(game.editorLayout!.gateSeams, before)
        XCTAssertTrue(game.editorCanUndo)
    }

    /// The start line's own seam stays gated — it is the finish line.
    func testTheStartSeamCannotBeUngated() throws {
        let game = try closedRing()
        game.editorMode = .gate
        let start = game.editorLayout!.pieces.firstIndex(of: PieceCatalog.startPieceID) ?? 0
        XCTAssertFalse(game.editorToggleGate(seam: start))
        XCTAssertTrue(game.editorLayout!.gateSeams.contains(start))
    }

    /// Gating stays undoable, and one toggle is one step.
    func testGatingInModeIsUndoable() throws {
        let game = try closedRing()
        game.editorMode = .gate
        let before = TrackCode.encode(game.editorLayout!)
        XCTAssertTrue(game.editorToggleGate(seam: 4))
        game.editorUndo()
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), before)
    }

    /// The 16-gate cap still holds inside the mode.
    func testTheGateCapStillHolds() throws {
        let game = try closedRing()
        game.editorMode = .gate
        let count = game.editorLayout!.pieces.count
        for seam in 1..<count { _ = game.editorToggleGate(seam: seam) }
        XCTAssertLessThanOrEqual(game.editorLayout!.gateSeams.count, 16)
    }

    /// Opening the editor starts in build mode, so a mode left on last time never
    /// greets the author as a surprise.
    func testOpeningTheEditorStartsInBuildMode() throws {
        let game = try closedRing()
        game.editorMode = .gate
        game.backToSetup()
        game.openEditor()
        XCTAssertEqual(game.editorMode, .build)
    }
}
