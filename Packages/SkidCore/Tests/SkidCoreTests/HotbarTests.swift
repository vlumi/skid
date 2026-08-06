import Foundation
import Testing

@testable import SkidCore
@testable import SkidKit

/// **The hotbar is sized to what can go in it, and never hides a feature.**
///
/// Both properties were reported from device: five fixed slots spent a strip of
/// screen on four placeholders for the sake of one button, and a stored bar assigned
/// when the palette still offered compounds kept a hairpin the picker can no longer
/// re-select — sitting in front of a newly-defaulted piece, so the new feature was
/// invisible on every install that had ever touched the editor.
@MainActor
struct HotbarTests {
    /// Mirrors `EditorView.hotbar`, which cannot be read without a live view.
    private func rendered(_ raw: String) -> [PieceID] {
        let stored = raw.split(separator: ",").compactMap { PieceID($0) }
            .filter { EditorView.hotbarPieces.contains($0) }
        let base = stored.isEmpty ? EditorView.HotbarSlot.defaults : stored
        return (0..<EditorView.HotbarSlot.count).map {
            $0 < base.count ? base[$0] : EditorView.HotbarSlot.empty
        }
    }

    @Test func theBarIsAsWideAsItsContents() {
        #expect(EditorView.HotbarSlot.count == EditorView.hotbarPieces.count)
        #expect(EditorView.HotbarSlot.count >= 1, "an empty row would be invisible")
    }

    /// Every default must be assignable, or the bar offers a button its own picker
    /// cannot restore once removed.
    @Test func everyDefaultIsAssignable() {
        for piece in EditorView.HotbarSlot.defaults {
            #expect(EditorView.hotbarPieces.contains(piece), "piece \(piece) is not offered")
        }
    }

    /// A bar full of ids the palette dropped describes a palette that no longer
    /// exists, so the defaults are a better answer than a row of dead buttons.
    @Test func staleStoredPiecesFallBackToTheDefaults() {
        // 15 and 19 are the hairpin and chicane compounds the palette retired.
        #expect(rendered("15,19,-2,-2,-2") == EditorView.HotbarSlot.defaults)
        #expect(rendered("-2,-2,-2,-2,-2") == EditorView.HotbarSlot.defaults)
        #expect(rendered("") == EditorView.HotbarSlot.defaults)
    }

    /// An assignment the author actually made is kept.
    @Test func anAssignedPieceSurvives() {
        let gap = PieceCatalog.ID.gap
        #expect(rendered("\(gap)").first == gap)
    }
}
