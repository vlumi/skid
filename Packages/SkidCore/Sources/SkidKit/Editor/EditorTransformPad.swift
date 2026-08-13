import SkidCore
import SwiftUI

/// **Undo, redo, and the whole-track transforms.**
///
/// Split from `EditorPaletteView.swift` to keep that file inside its length budget.
/// The transforms expand IN PLACE rather than in a sheet: they change the whole map,
/// and a sheet covers the one thing you need to watch.
extension EditorView {
    /// **Undo, redo, and everything else behind one button.**
    ///
    /// This was seven buttons in a row, and they are not alike: rotate, raise, lower
    /// and reverse are laid-out-ONCE operations, while undo and redo are used on every
    /// edit. Lumping them by object rather than by frequency is what made the row too
    /// wide — measured, this row wanted 478 pt on the 320 pt screen the project designs
    /// for, which is the reported "buttons and their labels don't fit at all anymore".
    ///
    /// So the five rare transforms collapse behind one button, and the two constant
    /// ones stay out where they can be hit without looking.
    @ViewBuilder
    var transformPad: some View {
        HStack(spacing: 6) {
            // Undo and redo stand down while the transforms are out: expanded, the two
            // together want the whole 320 pt of an SE's width, and the transform you
            // just made is undone by the transform button beside it (rotate back, lower
            // again) rather than by the undo arrow.
            if !showTransforms {
                mapAction(
                    "arrow.uturn.backward", tint: .white, label: "Undo",
                    enabled: game.editorCanUndo
                ) {
                    game.editorUndo()
                }
                mapAction(
                    "arrow.uturn.forward", tint: .white, label: "Redo",
                    enabled: game.editorCanRedo
                ) {
                    game.editorRedo()
                }
            }
            // **Expands in place rather than opening a sheet.** These change the whole
            // map, and the only way to judge a rotation or a height shift is to watch
            // the map change — a full-screen sheet covers the one thing you need to
            // see. Reported as "can't see what the buttons are doing".
            //
            // Collapsed to one button when closed, which is why they left the row
            // (seven buttons overflowed a 320 pt screen); expanded, they are the same
            // five buttons, and the map is still there.
            if showTransforms {
                transformRow
                mapAction(
                    "xmark", tint: .white, label: "Close transforms"
                ) {
                    showTransforms = false
                }
            } else {
                mapAction(
                    "slider.horizontal.below.rectangle", tint: .white,
                    label: "Transform the whole track"
                ) {
                    showTransforms = true
                }
            }
        }
    }

    /// The five whole-track transforms, as icon buttons beside the pad.
    ///
    /// Icons, not labels: labeling them is what made the original row too wide, and a
    /// row that stays on screen beside the map is worth more than the words. The
    /// accessibility label carries the meaning, as everywhere else in this bar.
    @ViewBuilder
    var transformRow: some View {
        // +eighths is counterclockwise in the ring but CLOCKWISE on screen: the canvas
        // is y-down and `screen()` doesn't flip. Hence the signs.
        mapAction("rotate.left", tint: .white, label: "Rotate 45° left") {
            game.editorRotate(eighths: -1)
        }
        mapAction("rotate.right", tint: .white, label: "Rotate 45° right") {
            game.editorRotate(eighths: 1)
        }
        mapAction(
            "arrow.up.to.line", tint: .white, label: "Raise track",
            enabled: game.canShiftHeight(steps: 1)
        ) {
            game.editorShiftHeight(steps: 1)
        }
        mapAction(
            "arrow.down.to.line", tint: .white, label: "Lower track",
            enabled: game.canShiftHeight(steps: -1)
        ) {
            game.editorShiftHeight(steps: -1)
        }
        // Reversing is a whole-track transform like rotating: same road, driven the
        // other way. Only a closed ring has a settled direction to flip.
        mapAction(
            "arrow.triangle.2.circlepath", tint: .white, label: "Reverse direction",
            enabled: game.editorCanReverseDirection
        ) {
            game.editorReverseDirection()
        }
    }
}
