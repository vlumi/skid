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

    /// Delete, anchored ON the selected piece rather than at a fixed spot.
    ///
    /// No build-end arrows: a piece has at most one free end (head at index 0, tail
    /// at the last), and selecting it already chooses that end — so the arrow was
    /// always the already-active one and tapping it did nothing. The construction
    /// marker shows which end is live.
    @ViewBuilder
    func selectionChrome(walk: WalkResult, transform: EditorRenderer.Transform) -> some View {
        if let index = game.editorSelectedPiece, walk.placed.indices.contains(index) {
            let placed = walk.placed[index]
            let anchor = transform.screen(placed.centerlineSamples().midpointSample)
            HStack(spacing: 8) {
                // Markings live behind a long press, not a second button: they are
                // a rarely-used variant, and the map has little room to spare.
                // (The plan's long-press-a-laid-piece, reached via the selection
                // rather than a raw map gesture — SpatialTapGesture is what carries
                // a location, and LongPressGesture does not.)
                if game.editorCanDeleteSelected {
                    mapAction("trash", tint: .white, label: "Delete piece") {
                        game.editorDeleteSelected()
                    }
                }
                mapAction(
                    game.editorLayout?.decal(at: index) == nil
                        ? "paintbrush" : "paintbrush.fill",
                    tint: .white, label: "Piece markings"
                ) {
                    configuring = .piece(index)
                }
            }
            .position(x: anchor.x, y: anchor.y - 34)
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
