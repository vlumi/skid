import SkidCore
import SwiftUI

/// **The line (or two) under the canvas: what the track is, and what it needs.**
///
/// Split from `EditorView.swift` on its length budget, and a real subject: the
/// closure hint answers "what do I do next", while the stats answer "what have I
/// made" — the numbers an author is aiming at while placing pieces (`TrackStats`).
extension EditorView {
    @ViewBuilder
    func buildStatus(walk: WalkResult) -> some View {
        // Save state, or how far the selected end is from closing — and what the
        // track has become, which is the number an author is building toward.
        VStack(spacing: 3) {
            statusLine(walk: walk)
            // **Live, as you build.** The shape of a track is length + corners +
            // climb, and knowing them while placing pieces is what lets an author
            // aim for a deliberate spread instead of measuring afterwards.
            trackStatsLine(walk: walk)
        }
    }

    /// Length, corners and climb for the road as it currently stands.
    @ViewBuilder
    private func trackStatsLine(walk: WalkResult) -> some View {
        let stats = TrackStats.of(walk: walk)
        HStack(spacing: 8) {
            Text(verbatim: "\(Int(stats.length))u")
            Text(verbatim: "\(stats.corners)⌒")
            // Left/right, so a track that only turns one way is visible while it
            // is still cheap to fix.
            if stats.corners > 0 {
                Text(verbatim: "\(stats.leftCorners)L/\(stats.rightCorners)R")
            }
            if stats.topLevel > 0 {
                Text(verbatim: "▲\(stats.topLevel)")
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(.black.opacity(0.35), in: Capsule())
    }

    @ViewBuilder
    private func statusLine(walk: WalkResult) -> some View {
        Group {
            if game.editorIsSaveable() {
                Text("Track complete", bundle: .module)
                    .font(Retro.caption)
                    .foregroundStyle(.white)
            } else if let gap = closureHint(walk) {
                Text(verbatim: gap)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text("Extend the loose end to close the loop", bundle: .module)
                    .font(Retro.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        // A backdrop, because the canvas-bounds dashes run right where
        // this line sits and made it hard to read.
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.black.opacity(0.35), in: Capsule())
    }

}
