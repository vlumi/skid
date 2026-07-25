import SkidCore
import SwiftUI

/// Overlays drawn on top of the ribbons: ramp climb-markers and the start line.
extension EditorRenderer {
    /// A tight ladder of uniform chevrons up the middle of a ramp, all pointing
    /// UPHILL (toward the higher end) — like a road "steep grade" sign, so a
    /// ramp reads as a climb at a glance. A launch piece uses yellow, a plain
    /// ramp white.
    static func drawRampChevrons(
        _ placed: PlacedPiece, width: Double, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        let poly = placed.centerlineSamples()
        guard poly.count >= 2 else { return }
        let color: Color = placed.piece.launches ? .yellow : .white
        // Uphill = direction of increasing height. On a flat launch (no
        // heightDelta) fall back to forward.
        let uphill = placed.piece.heightDelta >= 0
        // A tight LADDER of uniform chevrons EVENLY spaced by arc-length up the
        // ramp center, all pointing uphill — like a road "steep grade" sign.
        // (A straight ramp has only 2 centerline points, so pick positions by
        // interpolating along the polyline, not by sample index — otherwise
        // they'd all collapse onto one point.)
        let count = 3
        // World-scaled to the on-screen road width, so the ladder zooms with
        // the ramp and always reads proportionate.
        let span = max(3, width * t.scale * 0.2)
        for c in 1...count {
            let frac = Double(c) / Double(count + 1)
            let (pt, tangent) = pointOnPolyline(poly, atFraction: frac)
            let along = uphill ? tangent : Vec2(-tangent.x, -tangent.y)
            let base = t.screen(pt)
            // FLAT & WIDE: shallow forward depth, wider sideways reach, so it
            // reads as a grade marking on the road rather than a "go this way"
            // arrow. The tip still nods uphill just enough to show the slope.
            let depth = span * 0.5
            let halfW = span * 1.3
            let fx = CGFloat(along.x) * depth
            let fy = CGFloat(along.y) * depth
            let sx = CGFloat(-along.y) * halfW
            let sy = CGFloat(along.x) * halfW
            // Chevron tip points uphill; the two legs trail behind it.
            let tip = CGPoint(x: base.x + fx, y: base.y + fy)
            let lg = CGPoint(x: base.x - fx + sx, y: base.y - fy + sy)
            let rg = CGPoint(x: base.x - fx - sx, y: base.y - fy - sy)
            var chev = Path()
            chev.move(to: lg)
            chev.addLine(to: tip)
            chev.addLine(to: rg)
            context.stroke(
                chev, with: .color(color.opacity(0.85)),
                style: StrokeStyle(
                    lineWidth: max(1.5, span * 0.35), lineCap: .round, lineJoin: .round))
        }
    }

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

    /// All ground edge decoration for the whole layout, laid down BEFORE any
    /// asphalt: the thin white line every road carries, widened into a red/white
    /// kerb on the edges that earn one (a corner's apex, its exit, both sides of
    /// a chicane).
    ///
    /// Everything sits *outboard* of the grip surface — the band straddles the
    /// edge and the asphalt pass then covers its inner half — so decoration never
    /// narrows the road, and a kerb can't spill onto a neighboring piece's road
    /// because that road is painted afterwards.
    ///
    /// Done for the whole ring at once, not per piece, so a kerb that runs across
    /// several pieces is ONE stroke with ONE stripe length. Drawing it per piece
    /// gave each piece its own nearest-fit stripes, and the phases didn't line up
    /// across the joints — every internal boundary showed a visibly narrow white
    /// stripe.
    static func drawAllEdges(
        walk: WalkResult, kerbs: KerbPlan, width: Double, t: Transform,
        into context: inout GraphicsContext
    ) {
        for side in [true, false] {
            // Walk the ring gathering one continuous polyline per style run,
            // crossing piece boundaries wherever the style holds.
            var runPoints: [CGPoint] = []
            var runStyle: KerbPlan.Edge?
            func flush() {
                if let style = runStyle, runPoints.count >= 2 {
                    strokeEdge(runPoints, style: style, width: width, t: t, into: &context)
                }
                runPoints = []
                runStyle = nil
            }
            for (index, placed) in walk.placed.enumerated() {
                // Deck edges are guard rails, drawn over the road instead — they
                // also break any run in progress.
                guard placed.entryHeight <= 0.5, placed.exitHeight <= 0.5,
                    let e = edges(placed, width: width, t: t)
                else {
                    flush()
                    continue
                }
                let points = side ? e.left : e.right
                for sample in points.indices {
                    let pair = kerbs.style(piece: index, sample: sample)
                    let style = side ? pair.left : pair.right
                    if style != runStyle {
                        // Carry the joint point into the new run so runs abut.
                        let joint = runPoints.last
                        flush()
                        runStyle = style
                        if let joint { runPoints.append(joint) }
                    }
                    runPoints.append(points[sample])
                }
            }
            flush()
        }
    }

    /// One run of edge decoration. The band straddles the road edge and the
    /// asphalt pass covers its inner half, so what remains visible is the
    /// outboard part — which is why the stroke is drawn at twice the intended
    /// visible width.
    ///
    /// `points` is the run's polyline, used to measure its length: a kerb's
    /// stripes are sized to divide the run EVENLY, so every kerb starts and ends
    /// on a whole stripe instead of being cut off mid-red. A fixed dash length
    /// can't do that — no constant divides every corner's arc length.
    static func strokeEdge(
        _ points: [CGPoint], style: KerbPlan.Edge, width: Double, t: Transform,
        into context: inout GraphicsContext
    ) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        switch style {
        case .line:
            let band = max(1.5, Double(PieceCatalog.edgeLine) * 2 * t.scale)
            context.stroke(
                path, with: .color(kerbWhite),
                style: StrokeStyle(lineWidth: band, lineCap: .butt, lineJoin: .round))
        case .kerb:
            let band = max(3, Double(PieceCatalog.kerbBand) * 2 * t.scale)
            context.stroke(
                path, with: .color(kerbWhite),
                style: StrokeStyle(lineWidth: band, lineCap: .butt, lineJoin: .round))
            // Pick the stripe length nearest the target that fits a whole number
            // of red+white pairs into this run.
            let length = polylineLength(points)
            let target = width * 0.12 * t.scale
            let pairs = max(1, (length / (target * 2)).rounded())
            let dash = length / (pairs * 2)
            guard dash > 0.5 else { return }
            context.stroke(
                path, with: .color(kerbRed),
                style: StrokeStyle(
                    lineWidth: band, lineCap: .butt, lineJoin: .round, dash: [dash, dash]))
        }
    }

    static func polylineLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<points.count {
            total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return total
    }
}
