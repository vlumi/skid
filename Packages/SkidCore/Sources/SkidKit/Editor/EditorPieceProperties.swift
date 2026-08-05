import SkidCore
import SwiftUI

/// The selected piece's own properties — markings and railings.
///
/// Split from `EditorPaletteView.swift` to keep that file inside the length budget;
/// these are the controls for a piece you have already laid, as opposed to the
/// palette you lay pieces from.
extension EditorView {
    /// **Show each off-ground piece's storey.** A mode rather than always-on: on a
    /// flat track every badge would read "0", which is noise. Blocked pieces are
    /// flagged regardless of this toggle — a warning you have to switch on is not a
    /// warning.
    var levelsToggle: some View {
        Button {
            showLevels.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.3.layers.3d")
                Text("Levels", bundle: .module)
            }
            .font(.footnote.bold())
            .foregroundStyle(showLevels ? .black : .white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(showLevels ? Color.white : .black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityLabel(
            Text(showLevels ? "Hide piece levels" : "Show piece levels", bundle: .module))
    }

    /// **Whether the next piece you lay gets a railing.** Sticky, beside the mode
    /// toggle, because railing a bridge is a run of pieces — asking once beats
    /// toggling each one afterwards. The selected piece's own railing is toggled
    /// from its properties sheet instead.
    var railBuildToggle: some View {
        let on = game.editorRailNewPieces
        return Button {
            game.editorRailNewPieces.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: on ? "road.lanes" : "road.lanes.curved.right")
                Text("Rails", bundle: .module)
            }
            .font(.footnote.bold())
            .foregroundStyle(on ? .black : .white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(on ? EditorRenderer.bridgeRail : .black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityLabel(
            Text(on ? "Stop railing new pieces" : "Rail new pieces", bundle: .module))
    }

    /// **The railing toggle.** A railing is per placed piece, not per shape, so a
    /// bridge can have an open edge you drive off and a flat piece can be fenced.
    /// The sheet stays open: railing is the kind of thing you flip and look at.
    func railOption(at index: Int) -> some View {
        let railed = game.editorIsRailed(at: index)
        return Button {
            game.editorToggleRail(at: index)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: railed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(railed ? EditorRenderer.bridgeRail : .white.opacity(0.6))
                Text("Railings", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                .black.opacity(railed ? 0.5 : 0.22), in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(railed ? 0.8 : 0.25), lineWidth: railed ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// One markings option: no decal, or one of them. Applied in place — same
    /// geometry, different paint.
    func decalOption(_ decal: Decal?, at index: Int, chosen: Bool) -> some View {
        Button {
            game.editorSetDecal(decal, at: index)
            configuring = nil
        } label: {
            VStack(spacing: 6) {
                Image(systemName: decal == nil ? "slash.circle" : "arrow.up")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(EditorView.decalTint(decal))
                Text(EditorView.decalLabel(decal), bundle: .module)
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
            .frame(width: 84, height: 68)
            .background(.black.opacity(chosen ? 0.5 : 0.22), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(chosen ? 0.8 : 0.25), lineWidth: chosen ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
