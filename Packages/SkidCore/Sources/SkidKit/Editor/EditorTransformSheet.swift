import SkidCore
import SwiftUI

/// The whole-track transforms, in a sheet: turn either way, raise, lower, reverse.
///
/// Split from `EditorPaletteView.swift` to keep that file inside its length budget.
/// Behind a button because these are laid-out-once operations — see `transformPad`.
extension EditorView {
    var transformSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            // +eighths is counterclockwise in the ring but CLOCKWISE on screen: the
            // canvas is y-down and `screen()` doesn't flip. Hence the signs.
            transformRow("rotate.left", "Rotate 45° left", enabled: true) {
                game.editorRotate(eighths: -1)
            }
            transformRow("rotate.right", "Rotate 45° right", enabled: true) {
                game.editorRotate(eighths: 1)
            }
            transformRow(
                "arrow.up.to.line", "Raise track", enabled: game.canShiftHeight(steps: 1)
            ) {
                game.editorShiftHeight(steps: 1)
            }
            transformRow(
                "arrow.down.to.line", "Lower track",
                enabled: game.canShiftHeight(steps: -1)
            ) {
                game.editorShiftHeight(steps: -1)
            }
            // Reversing is a whole-track transform like rotating: same road, driven
            // the other way. Only a closed ring has a settled direction to flip.
            transformRow(
                "arrow.triangle.2.circlepath", "Reverse direction",
                enabled: game.editorCanReverseDirection
            ) {
                game.editorReverseDirection()
            }
        }
    }

    /// One row of the transform sheet: icon, label, and the action. Labelled, because
    /// fitting labels is why these left the button row.
    func transformRow(
        _ icon: String, _ label: String.LocalizationValue, enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 28)
                Text(String(localized: label, bundle: .module))
                    .font(.callout.weight(.medium))
                Spacer()
            }
            .foregroundStyle(enabled ? .white : .white.opacity(0.35))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
