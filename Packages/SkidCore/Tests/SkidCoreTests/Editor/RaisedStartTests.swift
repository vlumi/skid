import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **A raised start piece must be buildable and badged** — reported from device:
/// "I raised the start piece to the top level, but I can't add a ramp down from
/// it, and it doesn't show the level."
@MainActor
final class RaisedStartTests: XCTestCase {
    /// **Raising the track refreshes the placement verdicts.** The memo keyed on
    /// the piece list alone, and a whole-track raise changes only `originHeight`
    /// — so a descend refused at the ground floor stayed refused at the top (the
    /// grey button), and a climb allowed at the ground stayed allowed at the
    /// ceiling (an enabled button whose tap did nothing).
    func testARaiseRefreshesThePlacementVerdicts() {
        let game = CouchGame()
        game.editorLayout = TrackLayout(pieces: [PieceCatalog.startPieceID])
        game.editorSelect(0)
        let short = PieceCatalog.ID.shortStraight
        XCTAssertFalse(
            game.editorCanAppend(short, pitch: .down), "nothing descends below the floor")
        XCTAssertTrue(game.editorCanAppend(short, pitch: .up))
        game.editorShiftHeight(steps: 6)  // half-levels: to the very top
        XCTAssertTrue(
            game.editorCanAppend(short, pitch: .down),
            "the ramp down was still refused after the raise — the stale memo")
        XCTAssertFalse(
            game.editorCanAppend(short, pitch: .up), "nothing climbs past the ceiling")
        // And the allowed placement actually lands, descending.
        XCTAssertTrue(game.editorPlace(short, pitch: .down))
        let placed = game.editorLayout!.walk().placed
        XCTAssertEqual(placed.last!.entryHeight, 3.0)
        XCTAssertLessThan(placed.last!.exitHeight, 3.0)
    }

    /// **The badge sits mid-piece, not on the exit seam.** A straight's two
    /// centerline samples put `samples[count / 2]` at the EXIT — the lone start's
    /// finish line, where the seam chrome painted over its badge.
    func testTheBadgeAnchorsMidPiece() {
        var layout = TrackLayout(pieces: [PieceCatalog.startPieceID])
        layout.originHeight = 3.0
        let badges = EditorRenderer.levelBadges(
            walk: layout.walk(),
            query: .init(blockedPieces: [], showLevels: true, onlyLevel: nil),
            transform: EditorRenderer.Transform(scale: 1, offset: .zero))
        XCTAssertEqual(badges.count, 1)
        XCTAssertEqual(badges[0].level, 3)
        XCTAssertEqual(
            badges[0].at.x, 120, accuracy: 1e-9,
            "the badge left the piece's middle for a seam")
    }
}
