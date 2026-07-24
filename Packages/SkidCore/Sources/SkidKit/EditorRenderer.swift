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
        // Grass-colour fade over the last bit of road, covering the round cap
        // overhang and blending the opening into the field.
        let fadeLen = width * 0.55
        let backCenter = tip - fwd * fadeLen
        let hw = w / 2 + 8 * t.scale
        func s(_ v: Vec2) -> CGPoint { let p = t.screen(v); return CGPoint(x: p.x, y: p.y) }
        var fade = Path()
        fade.move(to: s(backCenter - side * (Double(width) / 2)))
        fade.addLine(to: s(tip - side * (Double(width) / 2)))
        fade.addLine(to: s(tip + side * (Double(width) / 2)))
        fade.addLine(to: s(backCenter + side * (Double(width) / 2)))
        fade.closeSubpath()
        context.fill(
            fade,
            with: .linearGradient(
                Gradient(colors: [grass.opacity(0), grass]),
                startPoint: t.screen(backCenter), endPoint: t.screen(tip)))

        // Hazard-striped cap bar across the opening.
        let capA = t.screen(tip - side * (Double(width) / 2))
        let capB = t.screen(tip + side * (Double(width) / 2))
        var cap = Path()
        cap.move(to: capA)
        cap.addLine(to: capB)
        let dash = max(4, 10 * t.scale)
        context.stroke(
            cap, with: .color(selected ? .yellow : Color(red: 0.95, green: 0.75, blue: 0.1)),
            style: StrokeStyle(
                lineWidth: max(5, hw * 0.5), lineCap: .butt, dash: [dash, dash]))
        context.stroke(
            cap, with: .color(.black.opacity(0.55)),
            style: StrokeStyle(
                lineWidth: max(5, hw * 0.5), lineCap: .butt, dash: [dash, dash], dashPhase: dash))

        // On the SELECTED end, a forward arrow showing where the next piece
        // will attach — the "build here" cue.
        if selected {
            drawAppendArrow(tip: tip, fwd: fwd, width: width, t: t, into: &context)
        }
    }

    /// A yellow forward arrow at the selected loose end, pointing where the
    /// next piece will attach.
    private static func drawAppendArrow(
        tip: Vec2, fwd: Vec2, width: Double, t: Transform,
        into context: inout GraphicsContext
    ) {
        let a = width * 0.35  // reach in world units
        let head = tip + fwd * a
        let wing = fwd.perpendicular * (a * 0.5)
        var arrow = Path()
        arrow.move(to: t.screen(tip + fwd * (a * 0.5)))
        arrow.addLine(to: t.screen(head))
        var wings = Path()
        wings.move(to: t.screen(head - fwd * (a * 0.4) + wing))
        wings.addLine(to: t.screen(head))
        wings.addLine(to: t.screen(head - fwd * (a * 0.4) - wing))
        let lw = max(3, 5 * t.scale)
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
        let samples = placed.heightedSamples()
        guard samples.count >= 2 else { return }

        // Centre + normal at each sample. Half-width scales with the height
        // there, so a ramp widens as it climbs. Pieces meet edge-to-edge (no
        // overlap): the end cuts are simply not stroked, so no kerb line shows
        // across a joint and nothing is hidden under a neighbour.
        var centre: [Vec2] = []
        var normal: [Vec2] = []
        var heights: [Double] = []
        for (i, s) in samples.enumerated() {
            let dir: Vec2
            if i == 0 {
                dir = (samples[1].point - s.point).normalized
            } else if i == samples.count - 1 {
                dir = (s.point - samples[i - 1].point).normalized
            } else {
                dir = (samples[i + 1].point - samples[i - 1].point).normalized
            }
            let half = width / 2 * Elevation.scale(atHeight: s.height)
            centre.append(s.point)
            normal.append(dir.perpendicular * half)
            heights.append(s.height)
        }

        let left = zip(centre, normal).map { t.screen($0 + $1) }
        let right = zip(centre, normal).map { t.screen($0 - $1) }
        var outline = Path()
        outline.addLines(left + right.reversed())
        outline.closeSubpath()

        let elevated = placed.entryHeight > 0.5 || placed.exitHeight > 0.5

        // Drop shadow — offset scales with the height at each point, so a ramp
        // casts a growing shadow (near-zero at the ground end, full at the
        // deck) instead of a flat height-1 slab.
        if elevated {
            var shLeft: [CGPoint] = []
            var shRight: [CGPoint] = []
            for i in centre.indices {
                let off = CGSize(width: 6 * heights[i], height: 11 * heights[i])
                shLeft.append(offset(t.screen(centre[i] + normal[i]), by: off))
                shRight.append(offset(t.screen(centre[i] - normal[i]), by: off))
            }
            var shadow = Path()
            shadow.addLines(shLeft + shRight.reversed())
            shadow.closeSubpath()
            context.fill(shadow, with: .color(.black.opacity(0.3)))
        }

        // Fill first, THEN rails only along the two SIDE edges (never across
        // the end cuts — that was the stray kerb line at joints).
        fillRoad(outline, placed: placed, samples: samples, t: t, into: &context)
        strokeSideRails(left: left, right: right, elevated: elevated, t: t, into: &context)
    }

    /// The two side edges (left, right) as open polylines — the kerb (ground)
    /// or guardrail (deck). NOT a closed loop, so the piece's entry/exit cuts
    /// carry no line and adjacent pieces' rails join seamlessly.
    private static func strokeSideRails(
        left: [CGPoint], right: [CGPoint], elevated: Bool, t: Transform,
        into context: inout GraphicsContext
    ) {
        var edges = Path()
        if let a = left.first {
            edges.move(to: a); left.dropFirst().forEach { edges.addLine(to: $0) }
        }
        if let b = right.first {
            edges.move(to: b)
            right.dropFirst().forEach { edges.addLine(to: $0) }
        }
        let band = max(2, 12 * t.scale)
        if elevated {
            context.stroke(
                edges, with: .color(.black.opacity(0.5)),
                style: StrokeStyle(lineWidth: band + 5, lineCap: .round, lineJoin: .round))
            context.stroke(
                edges, with: .color(bridgeRail),
                style: StrokeStyle(lineWidth: band + 2, lineCap: .round, lineJoin: .round))
        } else {
            context.stroke(
                edges, with: .color(kerbWhite),
                style: StrokeStyle(lineWidth: band, lineCap: .round, lineJoin: .round))
            context.stroke(
                edges, with: .color(kerbRed),
                style: StrokeStyle(
                    lineWidth: band, lineCap: .butt, lineJoin: .round, dash: [band * 2, band * 2]))
        }
    }

    private static func offset(_ p: CGPoint, by s: CGSize) -> CGPoint {
        CGPoint(x: p.x + s.width, y: p.y + s.height)
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

    /// Chevrons along a ramp/jump piece — a "this climbs / launches" marker.
    private static func drawRampChevrons(
        _ placed: PlacedPiece, width: Double, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        let pts = placed.centerlineSamples()
        guard pts.count >= 2 else { return }
        let color: Color = placed.piece.launches ? .yellow : .white
        // A few chevrons spaced along the piece.
        let count = 3
        for c in 1...count {
            let frac = Double(c) / Double(count + 1)
            let idx = min(pts.count - 2, Int(frac * Double(pts.count - 1)))
            let a = pts[idx]
            let b = pts[idx + 1]
            let fwd = (b - a).normalized
            let side = fwd.perpendicular * (width * 0.32)
            let tip = t.screen(a + fwd * (width * 0.28))
            let l = t.screen(a - side)
            let r = t.screen(a + side)
            var chev = Path()
            chev.move(to: l)
            chev.addLine(to: tip)
            chev.addLine(to: r)
            context.stroke(
                chev, with: .color(color.opacity(0.85)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
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
