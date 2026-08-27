import SkidCore
import SwiftUI

extension EditorRenderer {
    /// **The most world a track can have**, drawn as a quiet dotted frame so an
    /// author can see how much room is left.
    ///
    /// **What the rule actually is matters here.** A track is legal when its
    /// road's bounding box fits `TrackValidator.canvas` — a limit on the
    /// track's SIZE, not on where it sits. There is no wall at a fixed spot, so
    /// the frame is anchored to the footprint's own centre: as much room as
    /// the rules still permit around what is already built, and it re-centres
    /// as pieces are added.
    ///
    /// It is drawn at the limit PLUS everything the compiler frames beyond the
    /// road — the size the grass will reach when the road is at its maximum —
    /// so the grass can never poke outside it. And it is always the same quiet line: an earlier
    /// version turned an edge red when that axis was full, which read as an
    /// error on a track that was perfectly fine. The palette greying out
    /// already says "no more room this way"; the frame only has to show where
    /// the room ends.
    static func drawCanvasBounds(
        walk: WalkResult, t: Transform, into context: inout GraphicsContext
    ) {
        guard let box = maximumWorldBox(walk: walk, t: t) else { return }
        let line = max(1, 2 * t.scale)
        let dash = max(4, Double(PieceCatalog.unit) * 0.35 * t.scale)
        context.stroke(
            Path(box),
            with: .color(boundsFrame),
            style: StrokeStyle(lineWidth: line, lineCap: .round, dash: [dash, dash]))
    }

    /// The frame's screen rect, centred on the road's padded footprint: the
    /// canvas limit (which the validator measures with half a road of padding)
    /// grown on every side by what the compiler frames BEYOND that — the
    /// deck-widening allowance, the kerb and the run-off. Nil before the first
    /// piece.
    static func maximumWorldBox(walk: WalkResult, t: Transform) -> CGRect? {
        guard let footprint = walk.paddedFootprint() else { return nil }
        let beyond = PieceCompiler.frameBeyondCenterline - Double(PieceCatalog.width) / 2
        let limit = TrackValidator.canvas + Vec2(2 * beyond, 2 * beyond)
        let center = footprint.center
        return CGRect(
            x: (center.x - limit.x / 2) * t.scale + t.offset.width,
            y: (center.y - limit.y / 2) * t.scale + t.offset.height,
            width: limit.x * t.scale, height: limit.y * t.scale)
    }

    /// Nearly opaque white on purpose: a faint white blended with the grass into
    /// a dull pink that read as a warning.
    private static let boundsFrame = Color.white.opacity(0.75)
}
