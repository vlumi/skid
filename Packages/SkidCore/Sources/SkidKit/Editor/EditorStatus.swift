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
    ///
    /// **Words, not glyphs.** The first cut read `5141u 4⌒ 4L/0R ▲1`, which is a
    /// legend you have to have been told — and there is room to spell it out even
    /// on an SE, where the row is otherwise empty. Each figure is labelled with
    /// the unit under it, so the number stays big and the meaning is not guessed.
    @ViewBuilder
    private func trackStatsLine(walk: WalkResult) -> some View {
        let stats = TrackStats.of(walk: walk)
        HStack(spacing: 14) {
            figure(
                value: WorldScale.distanceLabel(units: stats.length, in: game.settings.units),
                label: Text("lap", bundle: .module))
            // Left/right on the corner count, so a track that only turns one way
            // is visible while it is still cheap to fix. Spelled "3 left, 1 right"
            // rather than "3L/1R" for the same reason as everything else here.
            if stats.corners > 0 {
                figure(
                    value: "\(stats.corners)",
                    label: cornerLabel(left: stats.leftCorners, right: stats.rightCorners))
            } else {
                figure(value: "0", label: Text("corners", bundle: .module))
            }
            if stats.topLevel > 0 {
                figure(
                    value: "\(stats.topLevel)",
                    label: stats.topLevel == 1
                        ? Text("level up", bundle: .module)
                        : Text("levels up", bundle: .module))
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }

    /// One figure: the number, and what it counts underneath it.
    private func figure(value: String, label: Text) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: value)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
            label
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    /// "corners" — or which way they go, when a track turns both ways. A track
    /// that only turns one way says just "left corners", which is the finding.
    private func cornerLabel(left: Int, right: Int) -> Text {
        if left > 0, right == 0 {
            return left == 1
                ? Text("left corner", bundle: .module) : Text("left corners", bundle: .module)
        }
        if right > 0, left == 0 {
            return right == 1
                ? Text("right corner", bundle: .module)
                : Text("right corners", bundle: .module)
        }
        return Text("corners, \(left) left", bundle: .module)
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
