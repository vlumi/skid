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
    private func rendered(_ raw: String, experimental: Bool = true) -> [PieceID] {
        let offered = EditorView.hotbarPieces(experimental: experimental)
        let stored = raw.split(separator: ",").compactMap { PieceID($0) }
            .filter { offered.contains($0) }
        let base = stored.isEmpty ? EditorView.HotbarSlot.defaults : stored
        return (0..<EditorView.HotbarSlot.count(experimental: experimental)).map {
            $0 < base.count ? base[$0] : EditorView.HotbarSlot.empty
        }
    }

    @Test func theBarIsAsWideAsItsContents() {
        let offered = EditorView.hotbarPieces(experimental: true)
        #expect(EditorView.HotbarSlot.count(experimental: true) == offered.count)
        #expect(EditorView.HotbarSlot.count(experimental: true) >= 1)
    }

    /// **With the flag off the row has nothing to hold**, so it is not drawn — the
    /// experimental blocks leave no empty slot behind.
    @Test func theRowIsEmptyWithoutTheExperimentalFlag() {
        #expect(EditorView.hotbarPieces(experimental: false).isEmpty)
    }

    /// Every default must be assignable, or the bar offers a button its own picker
    /// cannot restore once removed.
    @Test func everyDefaultIsAssignable() {
        let offered = EditorView.hotbarPieces(experimental: true)
        for piece in EditorView.HotbarSlot.defaults {
            #expect(offered.contains(piece), "piece \(piece) is not offered")
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
