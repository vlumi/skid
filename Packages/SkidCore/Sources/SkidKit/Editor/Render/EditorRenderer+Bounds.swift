import SkidCore
import SwiftUI

extension EditorRenderer {
    /// The build limit, drawn so it isn't invisible.
    ///
    /// **What the rule actually is matters here.** A track is legal when its
    /// *bounding box* fits `TrackValidator.canvas` — a limit on the track's
    /// SIZE, not on where it sits. There is no wall at a fixed spot on the
    /// grass, so drawing a fixed rectangle would be a lie: you can't fix a
    /// too-big track by moving it.
    ///
    /// So the box drawn is the **remaining allowance**, anchored to the
    /// footprint's own center: as much room as the rules still permit around
    /// what's already built. Run out of room on one axis and that pair of edges
    /// turns red, which says "this direction is full" — the actual reason the
    /// palette grays out.
    static func drawCanvasBounds(
        walk: WalkResult, t: Transform, into context: inout GraphicsContext
    ) {
        // The same padded footprint the validator measures, so the drawn box is
        // the rule rather than an approximation of it.
        guard let footprint = walk.paddedFootprint() else { return }
        let used = footprint.size
        let limit = TrackValidator.canvas
        let center = footprint.center

        let box = CGRect(
            x: (center.x - limit.x / 2) * t.scale + t.offset.width,
            y: (center.y - limit.y / 2) * t.scale + t.offset.height,
            width: limit.x * t.scale, height: limit.y * t.scale)

        // A hair of slack, so a track sitting exactly at the limit doesn't
        // flicker between "full" and "not" on rounding.
        let slack = Double(PieceCatalog.unit) / 2
        let fullX = used.x > limit.x - slack
        let fullY = used.y > limit.y - slack

        let line = max(1, 2 * t.scale)
        let dash = max(4, Double(PieceCatalog.unit) * 0.35 * t.scale)
        // The two axes are drawn separately so a full one can shout on its own.
        for (vertical, full) in [(false, fullY), (true, fullX)] {
            var path = Path()
            if vertical {
                path.move(to: CGPoint(x: box.minX, y: box.minY))
                path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
                path.move(to: CGPoint(x: box.maxX, y: box.minY))
                path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
            } else {
                path.move(to: CGPoint(x: box.minX, y: box.minY))
                path.addLine(to: CGPoint(x: box.maxX, y: box.minY))
                path.move(to: CGPoint(x: box.minX, y: box.maxY))
                path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
            }
            context.stroke(
                path,
                with: .color(full ? boundsFull : boundsFree),
                style: StrokeStyle(
                    lineWidth: full ? line * 2 : line, lineCap: .round, dash: [dash, dash]))
        }
    }

    /// Room left on this axis — a quiet boundary you build inside of.
    ///
    /// Nearly opaque white on purpose. A faint white (this was 0.3 alpha) blends
    /// with the grass into a dull pink that reads as a *warning*, so a track with
    /// plenty of room looked like it was jammed against the limit. The two states
    /// have to be unmistakable at a glance, on green.
    private static let boundsFree = Color.white.opacity(0.75)
    /// This axis is full: the reason pieces are being refused.
    private static let boundsFull = Color(red: 1.0, green: 0.25, blue: 0.2)
}
