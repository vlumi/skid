import SkidCore
import SwiftUI

/// Selecting a piece on the map: hit-testing a tap to a piece, and the chrome that
/// hangs off the selection (the arrows that pick a build end, and delete).
extension EditorView {
    /// The piece a tap means — see `WalkResult.piece(nearWorld:)`.
    ///
    /// A thin forwarder: the geometry lives in SkidCore so it can be tested, and this
    /// only converts the tap from screen space to world space.
    func piece(
        near point: CGPoint, walk: WalkResult, transform: EditorRenderer.Transform,
        onlyLevel: Int? = nil
    ) -> Int? {
        walk.piece(nearWorld: transform.world(point), onlyLevel: onlyLevel)
    }

    /// **What you can do to the selected piece** — delete it, mark it, rail it.
    ///
    /// A FIXED row, not chrome floating on the map. It used to sit 34 pt above the
    /// selected piece, which is over the road you tap next: reported as deleting a
    /// piece by accident while reaching for another. A fixed row also makes trimming
    /// fast, since the bin does not move between taps.
    ///
    /// Buttons are DISABLED rather than absent when nothing is selected, so the row
    /// never reflows and the bin is always in the same place.
    @ViewBuilder
    var selectionRow: some View {
        let index = game.editorSelectedPiece
        let hasPiece =
            index.map { game.editorLayout?.pieces.indices.contains($0) ?? false }
            ?? false
        HStack(spacing: 6) {
            mapAction(
                "trash", tint: .white, label: "Delete piece",
                enabled: game.editorCanDeleteSelected
            ) {
                game.editorDeleteSelected()
            }
            mapAction(
                index.flatMap { game.editorLayout?.decal(at: $0) } == nil
                    ? "paintbrush" : "paintbrush.fill",
                tint: .white, label: "Piece markings", enabled: hasPiece
            ) {
                if let index { configuring = .piece(index) }
            }
            let railed = index.map { game.editorIsRailed(at: $0) } == true
            mapAction(label: "Railings on this piece", enabled: hasPiece) {
                if let index { game.editorToggleRail(at: index) }
            } glyph: {
                RailGlyph(railed: railed)
            }
        }
    }
}

extension Array where Element == Vec2 {
    /// The sample nearest the middle of the run — where chrome for a whole piece
    /// belongs, rather than at an end it might share with a neighbour.
    var midpointSample: Vec2 {
        isEmpty ? Vec2(0, 0) : self[count / 2]
    }
}
