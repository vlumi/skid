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
        let w = width * t.scale

        // A piece is "elevated" if it's a ramp (the slope) or sits on the deck
        // (layer ≥ 1). Consecutive pieces in the SAME band (ground vs elevated)
        // are stroked as ONE continuous butt-capped path, so there are no
        // half-circle caps at interior joints, and the guardrail runs unbroken
        // ground→ramp→deck→ramp→ground across a bridge. Ground first, then the
        // elevated run on top (so a bridge crosses over the road beneath).
        let bands = elevationRuns(walk.placed)
        for run in bands where !run.elevated {
            strokeRun(run.pieces, w: w, elevated: false, t: t, into: &context)
        }
        for run in bands where run.elevated {
            strokeRun(run.pieces, w: w, elevated: true, t: t, into: &context)
        }
        // Slope chevrons on ramp pieces (drawn over the elevated ribbon).
        for placed in walk.placed where placed.piece.layerDelta != 0 || placed.piece.launches {
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

    /// A maximal run of consecutive pieces sharing an elevation band.
    private struct Run {
        var pieces: [PlacedPiece]
        var elevated: Bool
    }

    /// Split the placed pieces into consecutive same-band runs (ground vs
    /// elevated), preserving walk order.
    private static func elevationRuns(_ placed: [PlacedPiece]) -> [Run] {
        func elevated(_ p: PlacedPiece) -> Bool { p.entryLayer >= 1 || p.piece.layerDelta != 0 }
        var runs: [Run] = []
        for p in placed {
            if var last = runs.last, last.elevated == elevated(p) {
                last.pieces.append(p)
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(pieces: [p], elevated: elevated(p)))
            }
        }
        return runs
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
    }

    /// Stroke one continuous run of same-band pieces. BUTT caps: interior
    /// joints within the run are flush (no half-circle overhang), and the
    /// run's own ends are flat cuts — real loose ends get the construction
    /// treatment on top; a run that meets another band (a ramp mouth) meets it
    /// flush. Elevated runs (ramp + deck) carry a continuous light-blue
    /// guardrail, so the wall runs unbroken ground→bridge→ground.
    private static func strokeRun(
        _ placed: [PlacedPiece], w: Double, elevated: Bool, t: Transform,
        into context: inout GraphicsContext
    ) {
        var path = Path()
        for p in placed {
            for k in p.piece.paths.indices {
                let pts = p.centerlineSamples(path: k).map { t.screen($0) }
                guard let first = pts.first else { continue }
                path.move(to: first)
                for pt in pts.dropFirst() { path.addLine(to: pt) }
            }
        }
        // The deck sits closer to the camera: wider than ground road.
        let roadW = elevated ? w + 12 : w

        if elevated {
            var shadow = context
            shadow.translateBy(x: 6, y: 11)
            shadow.stroke(
                path, with: .color(.black.opacity(0.32)),
                style: StrokeStyle(lineWidth: roadW + 16, lineCap: .butt, lineJoin: .round))
            // Continuous light-blue guardrail: dark backing + bold blue rail.
            let wall = max(6, 16 * t.scale)
            context.stroke(
                path, with: .color(.black.opacity(0.5)),
                style: StrokeStyle(lineWidth: roadW + wall + 3, lineCap: .butt, lineJoin: .round))
            context.stroke(
                path, with: .color(bridgeRail),
                style: StrokeStyle(lineWidth: roadW + wall, lineCap: .butt, lineJoin: .round))
            context.stroke(
                path, with: .color(Color(white: 0.72)),
                style: StrokeStyle(lineWidth: roadW, lineCap: .butt, lineJoin: .round))
            return
        }

        // Ground road: striped red/white kerb, band + dash scaled to the world.
        let band = max(2, 12 * t.scale)
        let dash = max(3, 24 * t.scale)
        context.stroke(
            path, with: .color(kerbWhite),
            style: StrokeStyle(lineWidth: roadW + band, lineCap: .butt, lineJoin: .round))
        context.stroke(
            path, with: .color(kerbRed),
            style: StrokeStyle(
                lineWidth: roadW + band, lineCap: .butt, lineJoin: .round, dash: [dash, dash]))
        context.stroke(
            path, with: .color(asphalt),
            style: StrokeStyle(lineWidth: roadW, lineCap: .butt, lineJoin: .round))
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
