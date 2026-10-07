import SkidCore
import SwiftUI

/// **The editor on a big screen**: the tools dock against the map's sides
/// instead of stacking under it.
///
/// The phone layout is a column — top bar, map, then every tool in rows below
/// — because a phone is tall and narrow. On a Mac window or an iPad that column
/// stretched across the screen: tools in the bottom-left corner, the palette in
/// the middle, the modes far right. Here the same controls are docked where
/// they act: the selected piece's tools and history on the map's left edge,
/// the modes and the next piece's settings on its right, the next piece itself
/// under it.
///
/// **The docks keep their width whatever is showing**, as the phone's rows keep
/// their height: a dock that came and went would resize the map, which moves
/// the piece you just tapped (see `paletteBar`).
extension EditorView {
    /// Docks when there is room for them: a Mac window, an iPad either way up.
    /// A phone held sideways is wide but short — its docks would not fit
    /// beside a usable map — so it keeps the phone layout.
    static func usesDocks(in size: CGSize) -> Bool {
        size.width >= 700 && size.height >= 560
    }

    private static let leftDockWidth: CGFloat = 84
    private static let rightDockWidth: CGFloat = 132

    func dockedLayout(layout: TrackLayout, walk: WalkResult) -> some View {
        VStack(spacing: 0) {
            topBar
            HStack(alignment: .top, spacing: 12) {
                leftDock.frame(width: Self.leftDockWidth)
                mapRegion(layout: layout, walk: walk)
                rightDock(walk: walk).frame(width: Self.rightDockWidth)
            }
            .padding(.horizontal, 12)
            dockedBottomBar(walk: walk)
        }
    }

    /// The selected piece's tools, and the history beside them — two columns,
    /// so expanding the transforms grows the dock DOWN, not across the map.
    /// Empty (but still as wide) while gating, as the phone's rows are.
    private var leftDock: some View {
        HStack(alignment: .top, spacing: 6) {
            if game.editorMode == .build {
                VStack(spacing: 6) { selectionButtons }
                VStack(spacing: 6) { transformButtons }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 8)
    }

    /// The modes, then what shapes the next piece.
    private func rightDock(walk: WalkResult) -> some View {
        VStack(spacing: 12) {
            if game.editorMode == .build {
                levelsToggle
            }
            modeToggle
            if game.editorMode == .build {
                nextPieceSettings(walk: walk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 8)
    }

    /// Under the map: what the build is doing, and the next piece to lay.
    private func dockedBottomBar(walk: WalkResult) -> some View {
        VStack(spacing: 10) {
            if game.editorMode == .gate {
                gateModeHint(walk)
            } else {
                buildStatus(walk: walk)
                Text("NEXT PIECE", bundle: .module)
                    .font(Retro.caption)
                    .foregroundStyle(Retro.onGroundSoft)
                nextPieceButtons(walk: walk)
                if !EditorView.hotbarPieces(experimental: EditorView.experimentalGaps).isEmpty {
                    hotbarRow(walk: walk)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 20)
    }
}
