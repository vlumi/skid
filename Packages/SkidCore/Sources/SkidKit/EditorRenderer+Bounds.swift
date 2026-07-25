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
        let points = walk.placed.flatMap { $0.centerlineSamples() }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
            let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return }

        // Same half-width padding the validator measures with, so the drawn box
        // is the rule rather than an approximation of it.
        let half = Double(PieceCatalog.width) / 2
        let used = Vec2((maxX - minX) + 2 * half, (maxY - minY) + 2 * half)
        let limit = TrackValidator.canvas
        let center = Vec2((minX + maxX) / 2, (minY + maxY) / 2)

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
    private static let boundsFree = Color.white.opacity(0.3)
    /// This axis is full: the reason pieces are being refused.
    private static let boundsFull = Color(red: 0.95, green: 0.42, blue: 0.3).opacity(0.85)
}
