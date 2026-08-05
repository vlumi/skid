import SkidCore
import SwiftUI

/// **A road seen from above, with or without railings down its edges.**
///
/// Drawn rather than an SF Symbol. Every road glyph in the catalogue — `road.lanes`,
/// `road.lanes.curved.right` — says what SHAPE a road is, so the pair read as
/// "straight or curved" rather than "railed or open", which is what it was reported
/// as. Nothing stock says "barrier along both edges", and `fence` is iOS 17 while this
/// package targets 16.
///
/// Two strokes of asphalt grey with the rail's own light blue beside them, so the icon
/// is a small picture of what the map will look like. Same colour as the drawn rail
/// (`EditorRenderer.bridgeRail`), which is the cue that actually carries the meaning.
struct RailGlyph: View {
    /// Whether to draw the railings.
    let railed: Bool
    /// Tint for the road itself; the rails always use their own colour.
    var road: Color = .white

    var body: some View {
        // A fixed 20×16 canvas, so the glyph lines up with the SF Symbols beside it.
        Canvas { context, size in
            let inset = 2.0
            let top = inset
            let bottom = size.height - inset
            let left = size.width * 0.28
            let right = size.width * 0.72
            // The road: a band running away from the viewer.
            var band = Path()
            band.addRect(CGRect(x: left, y: top, width: right - left, height: bottom - top))
            context.fill(band, with: .color(road.opacity(0.55)))
            // Its centre line, so the band reads as road rather than as a bar.
            var centre = Path()
            centre.move(to: CGPoint(x: (left + right) / 2, y: top + 2))
            centre.addLine(to: CGPoint(x: (left + right) / 2, y: bottom - 2))
            context.stroke(
                centre, with: .color(road.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
            guard railed else { return }
            // The railings: a solid rail just outboard of each edge, which is exactly
            // where the renderer puts them.
            for x in [left - 2.0, right + 2.0] {
                var rail = Path()
                rail.move(to: CGPoint(x: x, y: top))
                rail.addLine(to: CGPoint(x: x, y: bottom))
                context.stroke(
                    rail, with: .color(EditorRenderer.bridgeRail),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .frame(width: 20, height: 16)
    }
}
