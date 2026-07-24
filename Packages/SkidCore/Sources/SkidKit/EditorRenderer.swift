import SkidCore
import SwiftUI

/// Draws a **partial** (not-yet-closed) track layout for the editor: the
/// placed pieces as an asphalt ribbon, the start/finish line, and the loose
/// ends as tap targets (the selected one highlighted). Separate from
/// `TrackRenderer`, which assumes a closed, compiled `Track`.
enum EditorRenderer {
    private static let asphalt = Color(white: 0.62)
    private static let kerbWhite = Color(white: 0.95)
    private static let kerbRed = Color(red: 0.82, green: 0.16, blue: 0.14)
    private static let grass = Color(red: 0.28, green: 0.55, blue: 0.23)
    /// Bridge guardrail — a bold light blue so walls read unmistakably as
    /// barriers, distinct from the grey road/kerb.
    private static let bridgeRail = Color(red: 0.55, green: 0.78, blue: 0.95)

    /// Screen radius of a loose-end tap dot.
    static let endHitRadius: CGFloat = 26

    struct Transform {
        var scale: CGFloat
        var offset: CGSize
        func screen(_ p: Vec2) -> CGPoint {
            CGPoint(x: p.x * scale + offset.width, y: p.y * scale + offset.height)
        }
    }

    static func draw(
        walk: WalkResult, width: Double, selectedEnd: Int?,
        transform t: Transform, into context: inout GraphicsContext
    ) {
        // Every piece is a width-varying RIBBON POLYGON: half-width at each
        // sample follows the height there (Elevation.scale), so a ramp widens
        // as it climbs and the deck is naturally wider — one formula, no
        // ground/deck/ramp special cases. Draw lowest height first so a bridge
        // paints over the road beneath it; equal heights keep walk order.
        let ordered = walk.placed.enumerated().sorted { a, b in
            let ha = a.element.entryHeight + a.element.exitHeight
            let hb = b.element.entryHeight + b.element.exitHeight
            return ha != hb ? ha < hb : a.offset < b.offset
        }
        // Two passes: ALL shadows first, then ALL road surfaces. Otherwise an
        // elevated piece's offset shadow lands on a neighbour's already-drawn
        // road (e.g. the down-ramp getting a dark smear from the deck's
        // shadow). Shadows under everything; surfaces on top, low-to-high.
        for (_, placed) in ordered {
            drawPieceShadow(placed, width: width, t: t, into: &context)
        }
        for (_, placed) in ordered {
            drawPieceRibbon(placed, width: width, t: t, into: &context)
        }
        // Launch/ramp chevrons on top.
        for placed in walk.placed where placed.piece.heightDelta != 0 || placed.piece.launches {
            drawRampChevrons(placed, width: width, transform: t, into: &context)
        }

        // Start/finish line at the start piece's exit.
        if let start = walk.placed.first(where: { $0.id == PieceCatalog.startPieceID }) {
            drawStartLine(start, width: width, transform: t, into: &context)
        }

        // Loose (unbuilt) ends get a construction treatment. That's every
        // walk openEnd, PLUS the back of the start piece whenever the loop
        // isn't closed (it's the closure target, so the walk doesn't list it,
        // but it's an open stub until something connects to it).
        var looseEnds = walk.openEnds
        if !walk.openEnds.isEmpty,
            let start = walk.placed.first(where: {
                $0.id == PieceCatalog.startPieceID
            })
        {
            // The start's entry pose, facing OUT of the piece (back down the road).
            looseEnds.append(
                PiecePose(position: start.entry.position, heading: start.entry.heading.reversed))
        }
        for (i, end) in looseEnds.enumerated() {
            drawLooseEnd(end, width: width, selected: i == selectedEnd, t: t, into: &context)
        }
    }

    /// A loose (unbuilt) end: fade the last stretch of road toward grass and
    /// stamp a hazard-striped bar across the opening, so it clearly needs
    /// finishing — never a clean rounded cap that looks intentional.
    private static func drawLooseEnd(
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
    private static func drawAppendArrow(
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

    /// Draw ONE piece as a width-varying ribbon: at each centerline sample the
    /// half-width scales with the height there (`Elevation.scale`), so a ramp
    /// is a true wedge (narrow at the ground, wide at the deck) and the deck is
    /// wider than the ground — all from one height formula. An elevated stretch
    /// gets a drop shadow + light-blue guardrail; the ground gets the red/white
    /// kerb. Filled polygons (not stroked centerlines), so joints never gap.
    private static func drawPieceRibbon(
        _ placed: PlacedPiece, width: Double, t: Transform,
        into context: inout GraphicsContext
    ) {
        guard let e = edges(placed, width: width, t: t) else { return }
        // Extend the FILL a hair (~0.6px) past both end cuts along the port
        // direction, so abutting pieces' fills overlap sub-pixel and the
        // antialiased seam shows no background hairline. Only the fill is
        // extended — the rails still stop at the true cut, so nothing visibly
        // pokes past a joint.
        let fillLeft = extendEnds(e.left, by: 0.6)
        let fillRight = extendEnds(e.right, by: 0.6)
        var outline = Path()
        outline.addLines(fillLeft + fillRight.reversed())
        outline.closeSubpath()

        let elevated = placed.entryHeight > 0.5 || placed.exitHeight > 0.5
        // Fill first, THEN rails only along the two SIDE edges (never across
        // the end cuts — that was the stray kerb line at joints).
        fillRoad(outline, placed: placed, samples: e.samples, t: t, into: &context)
        strokeSideRails(left: e.left, right: e.right, elevated: elevated, t: t, into: &context)
    }

    /// The elevated piece's drop shadow — offset scales with the height at each
    /// point, so a ramp casts a growing shadow (near-zero at the ground end,
    /// full at the deck). Drawn in a pass BEFORE any road surface so it never
    /// smears onto a neighbouring piece's road.
    private static func drawPieceShadow(
        _ placed: PlacedPiece, width: Double, t: Transform,
        into context: inout GraphicsContext
    ) {
        guard placed.entryHeight > 0.5 || placed.exitHeight > 0.5,
            let e = edges(placed, width: width, t: t)
        else { return }
        var shLeft: [CGPoint] = []
        var shRight: [CGPoint] = []
        for i in e.left.indices {
            let off = CGSize(width: 6 * e.heights[i], height: 11 * e.heights[i])
            shLeft.append(offset(e.left[i], by: off))
            shRight.append(offset(e.right[i], by: off))
        }
        var shadow = Path()
        shadow.addLines(shLeft + shRight.reversed())
        shadow.closeSubpath()
        context.fill(shadow, with: .color(.black.opacity(0.3)))
    }

    /// The ribbon geometry both the shadow and the surface pass read.
    private struct Ribbon {
        var left: [CGPoint]
        var right: [CGPoint]
        var heights: [Double]
        var samples: [(point: Vec2, height: Double)]
    }

    /// The ribbon's two screen-space side edges plus the per-sample heights.
    /// Half-width scales with the height (a ramp widens as it climbs). The END
    /// normals use the exact PORT heading (entry / exit pose), not the
    /// interpolated sample direction — so adjacent pieces, sharing a port pose,
    /// produce collinear end edges that abut with no grass sliver.
    private static func edges(_ placed: PlacedPiece, width: Double, t: Transform) -> Ribbon? {
        let samples = placed.heightedSamples()
        guard samples.count >= 2 else { return nil }
        let entryDir = Vec2(angle: placed.entry.heading.radians)
        let exitDir = Vec2(angle: placed.exits[0].heading.radians)
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        var heights: [Double] = []
        for (i, s) in samples.enumerated() {
            let dir: Vec2
            if i == 0 {
                dir = entryDir
            } else if i == samples.count - 1 {
                dir = exitDir
            } else {
                dir = (samples[i + 1].point - samples[i - 1].point).normalized
            }
            let normal = dir.perpendicular * (width / 2 * Elevation.scale(atHeight: s.height))
            left.append(t.screen(s.point + normal))
            right.append(t.screen(s.point - normal))
            heights.append(s.height)
        }
        return Ribbon(left: left, right: right, heights: heights, samples: samples)
    }

    /// The two side edges (left, right) as open polylines — the kerb (ground)
    /// or guardrail (deck). NOT a closed loop, so the piece's entry/exit cuts
    /// carry no line and adjacent pieces' rails join seamlessly.
    private static func strokeSideRails(
        left: [CGPoint], right: [CGPoint], elevated: Bool, t: Transform,
        into context: inout GraphicsContext
    ) {
        // Extend the rail ends a hair past the cut (same as the fill), so on a
        // big screen the kerb/wall of abutting pieces overlaps sub-pixel and
        // shows no hairline gap along the joint.
        let l = extendEnds(left, by: 0.6)
        let r = extendEnds(right, by: 0.6)
        var edges = Path()
        if let a = l.first {
            edges.move(to: a)
            l.dropFirst().forEach { edges.addLine(to: $0) }
        }
        if let b = r.first {
            edges.move(to: b)
            r.dropFirst().forEach { edges.addLine(to: $0) }
        }
        // Butt caps (not round): the rail ends flush with the piece cut, like
        // the road fill, instead of a half-disc poking past the joint.
        let band = max(2, 12 * t.scale)
        if elevated {
            context.stroke(
                edges, with: .color(.black.opacity(0.5)),
                style: StrokeStyle(lineWidth: band + 5, lineCap: .butt, lineJoin: .round))
            context.stroke(
                edges, with: .color(bridgeRail),
                style: StrokeStyle(lineWidth: band + 2, lineCap: .butt, lineJoin: .round))
        } else {
            context.stroke(
                edges, with: .color(kerbWhite),
                style: StrokeStyle(lineWidth: band, lineCap: .butt, lineJoin: .round))
            context.stroke(
                edges, with: .color(kerbRed),
                style: StrokeStyle(
                    lineWidth: band, lineCap: .butt, lineJoin: .round, dash: [band * 2, band * 2]))
        }
    }

    private static func offset(_ p: CGPoint, by s: CGSize) -> CGPoint {
        CGPoint(x: p.x + s.width, y: p.y + s.height)
    }

    /// Push a polyline's two endpoints outward along its own end direction by
    /// `d` screen points — so a filled ribbon overlaps its neighbour by a hair
    /// and the antialiased seam shows no background hairline.
    private static func extendEnds(_ pts: [CGPoint], by d: CGFloat) -> [CGPoint] {
        guard pts.count >= 2 else { return pts }
        var out = pts
        func unit(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let dx = a.x - b.x
            let dy = a.y - b.y
            let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
            return CGPoint(x: dx / len, y: dy / len)
        }
        let u0 = unit(pts[0], pts[1])
        out[0] = CGPoint(x: pts[0].x + u0.x * d, y: pts[0].y + u0.y * d)
        let n = pts.count - 1
        let un = unit(pts[n], pts[n - 1])
        out[n] = CGPoint(x: pts[n].x + un.x * d, y: pts[n].y + un.y * d)
        return out
    }

    private static let deckGrey = Color(white: 0.72)

    /// Fill the road surface: flat pieces solid (deck lighter), a ramp shaded
    /// dark(ground)→light(deck) so the slope reads.
    private static func fillRoad(
        _ outline: Path, placed: PlacedPiece,
        samples: [(point: Vec2, height: Double)], t: Transform,
        into context: inout GraphicsContext
    ) {
        guard placed.piece.heightDelta != 0 else {
            let elevated = placed.entryHeight > 0.5
            context.fill(outline, with: .color(elevated ? deckGrey : asphalt))
            return
        }
        let colors = placed.piece.heightDelta > 0 ? [asphalt, deckGrey] : [deckGrey, asphalt]
        context.fill(
            outline,
            with: .linearGradient(
                Gradient(colors: colors),
                startPoint: t.screen(samples.first!.point), endPoint: t.screen(samples.last!.point))
        )
    }

}

/// Overlays drawn on top of the ribbons: ramp climb-markers and the start line.
extension EditorRenderer {
    /// A tight ladder of uniform chevrons up the middle of a ramp, all pointing
    /// UPHILL (toward the higher end) — like a road "steep grade" sign, so a
    /// ramp reads as a climb at a glance. A launch piece uses yellow, a plain
    /// ramp white.
    fileprivate static func drawRampChevrons(
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
        // ramp centre, all pointing uphill — like a road "steep grade" sign.
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

    private static func drawStartLine(
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
