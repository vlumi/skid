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
            .font(Retro.caption)
            .foregroundStyle(levelFilter == .off ? Retro.ink : Retro.onHighlight)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(levelFilter == .off ? Retro.panel : Retro.highlight)
            // A MODE, so it reads pressed-in while on — the retro language's way of
            // saying "this stays on", against an action's raised face.
            .overlay(RetroBevel(inset: levelFilter != .off, thickness: 2))
            .contentShape(Rectangle())
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

    /// **Step the road down a level, where it stands.**
    ///
    /// There is no warp piece to place: a warp occupies no ground, so it is an
    /// ACTION on the loose end rather than a shape you position. Down deepens (the
    /// first tap creates it), up shallows and removes it at zero, so the two arrows
    /// are each other's inverse and a single warp is all that is ever stored.
    ///
    /// Down only, because nothing lifts a car: a road that warped upward could not
    /// be driven. Up here undoes a drop rather than climbing — that is what `pitch`
    /// is for.
    ///
    /// Takes the **current build height** so it can be shown between the arrows:
    /// "which level am I on?" is otherwise unanswerable while building, and it is
    /// the number both arrows move. Always visible, not only while a warp exists —
    /// knowing you are on the deck matters just as much when laying plain road.
    func warpStepper(height: Double) -> some View {
        HStack(spacing: 2) {
            warpArrow(deeper: false, symbol: "chevron.up")
            buildHeightReadout(height)
            warpArrow(deeper: true, symbol: "chevron.down")
        }
    }

    /// The build height in **levels**, as the author counts them: whole numbers where
    /// the road is on a storey, one decimal on a half-level (pitch's own quantum), so
    /// "1.5" reads as mid-climb rather than as a rounding artifact.
    private func buildHeightReadout(_ height: Double) -> some View {
        let whole = abs(height.rounded() - height) < 0.01
        return Text(whole ? "\(Int(height.rounded()))" : String(format: "%.1f", height))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 20, minHeight: 26)
            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel(Text("Building at level \(height)", bundle: .module))
    }

    private func warpArrow(deeper: Bool, symbol: String) -> some View {
        let enabled = game.editorCanStepWarp(deeper: deeper)
        return Button {
            game.editorStepWarp(deeper: deeper)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? .white : .white.opacity(0.3))
                .frame(width: 16, height: 26)
                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(
            Text(deeper ? "Drop the road a level" : "Raise the dropped road", bundle: .module))
    }

    /// **Whether the next piece you lay gets a wall.** Sticky, beside the mode
    /// toggle, because railing a bridge is a run of pieces — asking once beats
    /// toggling each one afterwards. The selected piece's own railing is toggled
    /// from its properties sheet instead.
    var railBuildToggle: some View {
        let on = game.editorRailNewPieces
        return Button {
            game.editorRailNewPieces.toggle()
        } label: {
            RailGlyph(railed: on, road: on ? Retro.onHighlight : .white)
                .frame(width: 34, height: 26)
                .background(on ? Retro.highlight : Retro.panel.opacity(0.35))
                // A sticky setting for the NEXT piece, so it reads pressed-in while
                // armed — same grammar as the mode toggles.
                .overlay(RetroBevel(inset: on, thickness: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(on ? "Stop walling new pieces" : "Wall new pieces", bundle: .module))
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
                    .font(Retro.caption)
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
