import SkidCore
import SwiftUI

/// Chrome for the editor's two modes: the selected piece, and the seams gate mode
/// offers to tap.
extension EditorRenderer {
    /// The selected piece: its own stretch of road outlined, so it is obvious what
    /// delete would remove. Traced along the centerline at road width rather than
    /// boxed, so a curve reads as the curve it is.
    static func drawSelection(
        _ placed: PlacedPiece, width: Double, t: Transform,
        into context: inout GraphicsContext
    ) {
        let samples = placed.centerlineSamples()
        guard samples.count > 1 else { return }
        var path = Path()
        path.move(to: t.screen(samples[0]))
        for point in samples.dropFirst() { path.addLine(to: t.screen(point)) }
        // A wash over the piece's own asphalt — light enough that the road, its
        // kerbs and any gate on it still read through.
        //
        // Scaled by the piece's height, like the ribbon it covers: a flat `width`
        // left a raised piece's wash narrower than its own road, so the selection
        // looked like it was on a different, thinner piece.
        let top = max(placed.entryHeight, placed.exitHeight)
        context.stroke(
            path, with: .color(.yellow.opacity(0.22)),
            style: StrokeStyle(
                lineWidth: width * Elevation.scale(atHeight: top) * t.scale,
                lineCap: .butt, lineJoin: .round)
        )
        // Plus a bright spine, which is what actually catches the eye at a glance.
        context.stroke(
            path, with: .color(.yellow.opacity(0.9)),
            style: StrokeStyle(lineWidth: max(2, 3 * t.scale), lineCap: .round))
    }

    /// A seam that COULD be gated, shown only in gate mode: a thin dashed bar
    /// across the road. Without it the author has to guess where the taps land.
    static func drawGateCandidate(
        _ placed: PlacedPiece, width: Double, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        let pose = placed.exits[0]
        let across = Vec2(angle: pose.heading.radians).perpendicular
        let center = pose.position.vec2
        let edge = across * (width / 2)
        let lineWidth = max(1, 3 * t.scale)
        var bar = Path()
        bar.move(to: t.screen(center - edge))
        bar.addLine(to: t.screen(center + edge))
        context.stroke(
            bar, with: .color(.white.opacity(0.4)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, dash: [lineWidth * 3]))
    }

    /// A loose (unbuilt) end: fade the last stretch of road toward grass and
    /// stamp a hazard-striped bar across the opening, so it clearly needs
    /// finishing — never a clean rounded cap that looks intentional.
    static func drawLooseEnd(
        _ end: PiecePose, width: Double, selected: Bool, t: Transform,
        into context: inout GraphicsContext
    ) {
        let w = width * t.scale
        let fwd = Vec2(angle: end.heading.radians)
        let side = fwd.perpendicular
        let tip = end.position.vec2
        // No grass-fade: on an elevated loose end it faded the deck into grass
        // mid-air (wrong), and now that piece ends are cut square (butt caps)
        // there's no round overhang to cover. The hazard bar + arrow alone read
        // clearly as "unfinished, build here".

        // Hazard-striped cap bar across the opening — fully WORLD-scaled (band
        // + dash proportional to the on-screen road width `w`), so it zooms
        // with the piece it marks and always reads proportionate, like the
        // kerbs and start line.
        let capA = t.screen(tip - side * (Double(width) / 2))
        let capB = t.screen(tip + side * (Double(width) / 2))
        var cap = Path()
        cap.move(to: capA)
        cap.addLine(to: capB)
        let capBand = max(2, w * 0.22)
        let capDash = max(2, w * 0.18)
        context.stroke(
            cap, with: .color(selected ? .yellow : Color(red: 0.95, green: 0.75, blue: 0.1)),
            style: StrokeStyle(
                lineWidth: capBand, lineCap: .butt, dash: [capDash, capDash]))
        context.stroke(
            cap, with: .color(.black.opacity(0.55)),
            style: StrokeStyle(
                lineWidth: capBand, lineCap: .butt, dash: [capDash, capDash], dashPhase: capDash))

        // On the SELECTED end, a forward arrow showing where the next piece
        // will attach — the "build here" cue. Scaled to the road width too.
        if selected {
            drawAppendArrow(tip: tip, fwd: fwd, roadOnScreen: w, t: t, into: &context)
        }
    }

    /// A yellow forward arrow at the selected loose end, pointing where the
    /// next piece will attach. WORLD-scaled to the on-screen road width, so it
    /// zooms with the piece and always reads proportionate.
    static func drawAppendArrow(
        tip: Vec2, fwd: Vec2, roadOnScreen: CGFloat, t: Transform,
        into context: inout GraphicsContext
    ) {
        let base = t.screen(tip)
        // Screen-space forward / side unit vectors (y-down canvas).
        let f = CGVector(dx: fwd.x, dy: fwd.y)
        let sdv = CGVector(dx: -fwd.y, dy: fwd.x)
        // Proportional to the road width, so it scales with zoom.
        let reach = roadOnScreen * 0.55
        let wing = reach * 0.5
        func pt(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(
                x: base.x + f.dx * along + sdv.dx * across,
                y: base.y + f.dy * along + sdv.dy * across)
        }
        var arrow = Path()
        arrow.move(to: pt(reach * 0.5, 0))
        arrow.addLine(to: pt(reach, 0))
        var wings = Path()
        wings.move(to: pt(reach - wing, wing))
        wings.addLine(to: pt(reach, 0))
        wings.addLine(to: pt(reach - wing, -wing))
        let lw = max(2, reach * 0.16)
        context.stroke(
            arrow, with: .color(.yellow), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        context.stroke(
            wings, with: .color(.yellow),
            style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
    }
}
