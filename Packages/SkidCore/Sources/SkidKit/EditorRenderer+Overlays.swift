import SkidCore
import SwiftUI

/// Overlays drawn on top of the ribbons: ramp climb-markers and the start line.
extension EditorRenderer {

    /// Point + unit tangent at `frac` (0…1) of a polyline's total length.
    private static func pointOnPolyline(_ poly: [Vec2], atFraction frac: Double)
        -> (Vec2, Vec2)
    {
        var lengths: [Double] = []
        var total = 0.0
        for i in 1..<poly.count {
            let seg = (poly[i] - poly[i - 1]).length
            lengths.append(seg)
            total += seg
        }
        guard total > 0 else { return (poly[0], Vec2(1, 0)) }
        var target = frac * total
        for i in 1..<poly.count {
            let seg = lengths[i - 1]
            if target <= seg || i == poly.count - 1 {
                let u = seg > 0 ? target / seg : 0
                let a = poly[i - 1]
                let b = poly[i]
                let p = a + (b - a) * u
                return (p, (b - a).normalized)
            }
            target -= seg
        }
        return (poly[poly.count - 1], (poly[poly.count - 1] - poly[poly.count - 2]).normalized)
    }

    /// The grid-slot markings painted on the start piece's pavement: a short
    /// hash across the front edge of each slot, like real grid boxes, at
    /// exactly the positions the compiler puts the cars. Drawn before the
    /// start/finish line so the line reads on top.
    static func drawGridMarkings(
        _ start: PlacedPiece, width: Double, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        let pose = start.exits[0]
        let fwd = Vec2(angle: pose.heading.radians)
        let side = fwd.perpendicular
        let slots = PieceCompiler.Grid.positions(line: pose.position.vec2, dir: fwd)
        // A hash sits at the slot's FRONT edge (toward the line), spanning a bit
        // wider than a car — world-scaled so it zooms with the road.
        let halfHash = CarGeometry.width * 0.62
        let ahead = CarGeometry.length / 2
        let lineW = max(1.5, 5 * t.scale)
        for slot in slots {
            let front = slot + fwd * ahead
            var hash = Path()
            hash.move(to: t.screen(front - side * halfHash))
            hash.addLine(to: t.screen(front + side * halfHash))
            context.stroke(
                hash, with: .color(.white.opacity(0.85)),
                style: StrokeStyle(lineWidth: lineW, lineCap: .butt))
        }
    }

    /// A checkpoint gate across a seam: a line at the piece's ENTRY port, with a
    /// post at each road edge — the same read as the game's gates, so what you
    /// mark in the editor is what you'll drive through.
    static func drawGate(
        _ placed: PlacedPiece, width: Double, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        let pose = placed.entry
        let across = Vec2(angle: pose.heading.radians).perpendicular
        let center = pose.position.vec2
        let edge = across * (width / 2)
        let lineWidth = max(2, 6 * t.scale)

        // Across the road, solid: the part of the gate you always cross.
        var road = Path()
        road.move(to: t.screen(center - edge))
        road.addLine(to: t.screen(center + edge))
        context.stroke(
            road, with: .color(.cyan.opacity(0.75)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))

        // Onto the grass, faded: running wide still counts, out to roughly here.
        // (The compiler caps this side near a neighboring lane, so it's shown
        // as a soft reach rather than a hard edge.)
        let reach = across * (width / 2 + width)
        for direction in [1.0, -1.0] {
            var apron = Path()
            apron.move(to: t.screen(center + edge * direction))
            apron.addLine(to: t.screen(center + reach * direction))
            context.stroke(
                apron, with: .color(.cyan.opacity(0.28)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, dash: [lineWidth * 2]))
        }

        // Posts at the road edges, so a gate reads as a gate.
        let post = max(3, 9 * t.scale)
        for end in [center - edge, center + edge] {
            let box = CGRect(
                x: t.screen(end).x - post / 2, y: t.screen(end).y - post / 2,
                width: post, height: post)
            context.fill(Path(ellipseIn: box), with: .color(.cyan))
        }
    }

    static func drawStartLine(
        _ start: PlacedPiece, width: Double, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        let pose = start.exits[0]
        let fwd = Vec2(angle: pose.heading.radians)
        let side = fwd.perpendicular * (width / 2)
        let a = t.screen(pose.position.vec2 - side)
        let b = t.screen(pose.position.vec2 + side)
        var line = Path()
        line.move(to: a)
        line.addLine(to: b)
        // Width + dash scale with the world (like the kerbs), so the line
        // shrinks evenly on zoom-out instead of leaving fixed-size dashes.
        let lineW = max(2, 7 * t.scale)
        let dash = max(3, 9 * t.scale)
        context.stroke(
            line, with: .color(.white),
            style: StrokeStyle(lineWidth: lineW, dash: [dash, dash]))
    }

}
