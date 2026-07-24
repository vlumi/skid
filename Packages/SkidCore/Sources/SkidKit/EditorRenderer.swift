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

        // Draw in elevation order so a bridge visibly crosses over the road
        // beneath it: ground road → ramp slopes → the raised deck on top.
        // A ramp piece is the SLOPE connecting ground (layer 0) to deck
        // (layer ≥ 1); it's not part of either flat ribbon.
        let isRamp: (PlacedPiece) -> Bool = { $0.piece.layerDelta != 0 }
        let ground = walk.placed.filter { $0.entryLayer <= 0 && !isRamp($0) }
        let deck = walk.placed.filter { $0.entryLayer >= 1 && !isRamp($0) }

        strokeRibbon(ground, w: w, elevated: false, t: t, into: &context)
        for placed in walk.placed where isRamp(placed) {
            drawRampSlope(placed, width: width, w: w, transform: t, into: &context)
        }
        if !deck.isEmpty {
            strokeRibbon(deck, w: w, elevated: true, t: t, into: &context)
        }
        // Jumps (no layer change, but launch) still get chevrons on flat road.
        for placed in walk.placed where placed.piece.launches && placed.piece.layerDelta == 0 {
            drawRampChevrons(placed, width: width, transform: t, into: &context)
        }

        // Start/finish line at the start piece's exit.
        if let start = walk.placed.first(where: { $0.id == PieceCatalog.startPieceID }) {
            drawStartLine(start, width: width, transform: t, into: &context)
        }

        // Loose ends: an "unfinished" treatment — the road fades out into
        // grass with a hazard-striped cap, rather than a solid rounded
        // terminus, so it reads as "build here". The selected end is brighter.
        for (i, end) in walk.openEnds.enumerated() {
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
    }

    /// Stroke a set of placed pieces as a ribbon. The elevated deck is lighter
    /// with a drop shadow so it reads as raised over the ground layer.
    private static func strokeRibbon(
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
        // The deck sits closer to the camera: wider than ground road, matching
        // the ramp wedge's wider deck end (w/2 + 6 half → w + 12 full).
        let roadW = elevated ? w + 12 : w

        if elevated {
            var shadow = context
            shadow.translateBy(x: 6, y: 11)
            shadow.stroke(
                path, with: .color(.black.opacity(0.32)),
                style: StrokeStyle(lineWidth: roadW + 16, lineCap: .round, lineJoin: .round))
        }

        if elevated {
            // Bridge: a raised deck with substantial light-blue GUARDRAILS —
            // a dark backing so the rail edge reads, a bold blue rail, then the
            // road inset, so the walls are unmistakable (can't fall off).
            let wall = max(6, 16 * t.scale)
            context.stroke(
                path, with: .color(.black.opacity(0.5)),
                style: StrokeStyle(lineWidth: roadW + wall + 3, lineCap: .round, lineJoin: .round))
            context.stroke(
                path, with: .color(bridgeRail),
                style: StrokeStyle(lineWidth: roadW + wall, lineCap: .round, lineJoin: .round))
            context.stroke(
                path, with: .color(Color(white: 0.72)),
                style: StrokeStyle(lineWidth: roadW, lineCap: .round, lineJoin: .round))
            return
        }

        // Ground road: striped red/white kerb, band + dash scaled to the world
        // so zoom-out shrinks stripes evenly rather than leaving blobs.
        let band = max(2, 12 * t.scale)
        let dash = max(3, 24 * t.scale)
        context.stroke(
            path, with: .color(kerbWhite),
            style: StrokeStyle(lineWidth: roadW + band, lineCap: .round, lineJoin: .round))
        context.stroke(
            path, with: .color(kerbRed),
            style: StrokeStyle(
                lineWidth: roadW + band, lineCap: .butt, lineJoin: .round, dash: [dash, dash]))
        context.stroke(
            path, with: .color(asphalt),
            style: StrokeStyle(lineWidth: roadW, lineCap: .round, lineJoin: .round))
    }

    /// A ramp piece drawn as a gradient slope wedge (ground → deck), with
    /// white edges and drive-direction chevrons — the same visual language as
    /// the game's ramps, so it reads as a climb/descent, not a floating pill.
    private static func drawRampSlope(
        _ placed: PlacedPiece, width: Double, w: Double, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        // Ramp is a straight: entry→exit. Up-ramp climbs entry(ground)→exit(deck);
        // down-ramp descends entry(deck)→exit(ground).
        let up = placed.piece.layerDelta > 0
        let groundWorld = up ? placed.entry.position.vec2 : placed.exits[0].position.vec2
        let deckWorld = up ? placed.exits[0].position.vec2 : placed.entry.position.vec2
        let gScreen = t.screen(groundWorld)
        let dScreen = t.screen(deckWorld)
        let gv = Vec2(gScreen.x, gScreen.y)
        let dv = Vec2(dScreen.x, dScreen.y)
        let axis = dv - gv
        let len = axis.length
        guard len > 0.5 else { return }
        let dir = Vec2(axis.x / len, axis.y / len)
        let side = dir.perpendicular
        // Deck end a touch wider, like the game's wedge.
        let gHalf = side * (w / 2)
        let dHalf = side * (w / 2 + 6)
        func pt(_ v: Vec2) -> CGPoint { CGPoint(x: v.x, y: v.y) }

        var wedge = Path()
        wedge.move(to: pt(gv - gHalf))
        wedge.addLine(to: pt(dv - dHalf))
        wedge.addLine(to: pt(dv + dHalf))
        wedge.addLine(to: pt(gv + gHalf))
        wedge.closeSubpath()
        context.fill(
            wedge,
            with: .linearGradient(
                Gradient(colors: [asphalt, Color(white: 0.72)]),
                startPoint: pt(gv), endPoint: pt(dv)))
        for sign in [-1.0, 1.0] {
            var edge = Path()
            edge.move(to: pt(gv + gHalf * sign))
            edge.addLine(to: pt(dv + dHalf * sign))
            context.stroke(edge, with: .color(kerbWhite), lineWidth: max(2, 4 * t.scale))
        }
        // Chevrons up the slope, pointing the drive direction (piece order).
        let drive = (placed.exits[0].position.vec2 - placed.entry.position.vec2).normalized
        drawSlopeChevrons(
            ground: gv, deck: dv, drive: drive, wing: side * (w * 0.28), into: &context)
    }

    private static func drawSlopeChevrons(
        ground: Vec2, deck: Vec2, drive: Vec2, wing: Vec2, into context: inout GraphicsContext
    ) {
        let axis = deck - ground
        let len = axis.length
        guard len > 0 else { return }
        let up = Vec2(axis.x / len, axis.y / len)
        let driveScreen = Vec2(drive.x, drive.y)
        for frac in [0.3, 0.55, 0.8] {
            let base = ground + up * (len * frac) - driveScreen * 6
            let tip = base + driveScreen * 12
            var chev = Path()
            chev.move(to: CGPoint(x: (base - wing).x, y: (base - wing).y))
            chev.addLine(to: CGPoint(x: tip.x, y: tip.y))
            chev.addLine(to: CGPoint(x: (base + wing).x, y: (base + wing).y))
            context.stroke(
                chev, with: .color(.white.opacity(0.6)),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }

    /// Chevrons along a jump piece (flat road, launches) — a "this launches"
    /// marker versus plain road.
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
