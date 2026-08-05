import SkidCore
import SwiftUI

/// The selected piece's own properties — markings and railings.
///
/// Split from `EditorPaletteView.swift` to keep that file inside the length budget;
/// these are the controls for a piece you have already laid, as opposed to the
/// palette you lay pieces from.
extension EditorView {
    /// **Which storey the editor is working on.** Cycles off → all → each storey the
    /// track actually uses → off.
    ///
    /// A picker rather than a badge toggle, because on a stack a tap is ambiguous and
    /// something has to disambiguate it. Cycling the BUTTON is safe where cycling the
    /// tap is not: the state is visible, and panning or zooming cannot change what
    /// your next tap will select.
    var levelsToggle: some View {
        let label: String
        switch levelFilter {
        case .off: label = ""
        case .all: label = "All"
        case .storey(let level): label = "\(level)"
        }
        return Button {
            levelFilter = nextLevelFilter()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.3.layers.3d")
                if label.isEmpty {
                    Text("Levels", bundle: .module)
                } else {
                    Text(verbatim: label)
                }
            }
            .font(.footnote.bold())
            .foregroundStyle(levelFilter == .off ? .white : .black)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(levelFilter == .off ? .black.opacity(0.55) : Color.white, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityLabel(Text("Level filter", bundle: .module))
    }

    /// The next filter in the cycle, listing only storeys the track uses — offering
    /// "level 2" on a flat track is a state that selects nothing.
    private func nextLevelFilter() -> LevelFilter {
        let used = Set(
            (game.editorLayout?.walk().placed ?? [])
                .map { Track.level(of: max($0.entryHeight, $0.exitHeight)) }
        ).sorted()
        switch levelFilter {
        case .off:
            // A flat track has one storey, so filtering by it is the same as `all`.
            return used.count > 1 ? .all : .off
        case .all:
            return used.first.map { .storey($0) } ?? .off
        case .storey(let level):
            guard let at = used.firstIndex(of: level), at + 1 < used.count else { return .off }
            return .storey(used[at + 1])
        }
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
            Image(systemName: on ? "road.lanes" : "road.lanes.curved.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(on ? .black : .white)
                .frame(width: 34, height: 26)
                .background(
                    on ? Color.white : .black.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(.white.opacity(on ? 0.9 : 0.3), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
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
