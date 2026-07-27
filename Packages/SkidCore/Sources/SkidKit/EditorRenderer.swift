import SkidCore
import SwiftUI

/// Draws a **partial** (not-yet-closed) track layout for the editor: the
/// placed pieces as an asphalt ribbon, the start/finish line, and the loose
/// ends as tap targets (the selected one highlighted). Separate from
/// `TrackRenderer`, which assumes a closed, compiled `Track`.
enum EditorRenderer {
    private static let asphalt = Color(white: 0.62)
    static let kerbWhite = Color(white: 0.95)
    static let kerbRed = Color(red: 0.82, green: 0.16, blue: 0.14)
    private static let grass = Color(red: 0.28, green: 0.55, blue: 0.23)
    /// Bridge guardrail — a bold light blue so walls read unmistakably as
    /// barriers, distinct from the gray road/kerb.
    private static let bridgeRail = Color(red: 0.55, green: 0.78, blue: 0.95)

    /// Screen radius of a loose-end tap dot.
    static let endHitRadius: CGFloat = 26

    struct Transform {
        /// World space unchanged — for callers whose context is already scaled
        /// and translated (the race view).
        static let identity = Transform(scale: 1, offset: .zero)

        var scale: CGFloat
        var offset: CGSize
        func screen(_ p: Vec2) -> CGPoint {
            CGPoint(x: p.x * scale + offset.width, y: p.y * scale + offset.height)
        }
    }

    static func draw(
        walk: WalkResult, width: Double, selectedEnd: Int?, gateSeams: [Int] = [],
        transform t: Transform, into context: inout GraphicsContext
    ) {
        // The size limit, made visible. Under everything else, since it's a
        // boundary you build inside of.
        drawCanvasBounds(walk: walk, t: t, into: &context)
        drawTrack(walk: walk, width: width, gateSeams: gateSeams, transform: t, into: &context)

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

    /// **The track itself** — shadows, edge decoration, asphalt, ramp markings,
    /// gates, grid and start line. No editor chrome.
    ///
    /// Shared with the race view, which is the whole point: two separate
    /// renderers over two different inputs (placed pieces here, a compiled
    /// `Track` there) drifted apart in kerbs, rails and ramp markings, and every
    /// fix had to be made twice. Now what you build is literally what you drive,
    /// because it is the same drawing code over the same placed pieces.
    /// `heightRange` limits which pieces are drawn, so a caller can interleave
    /// something between the levels. The race view needs exactly that: it draws
    /// the ground, then the cars on the ground, then the bridge over them, then
    /// the cars up on the bridge — otherwise a car under the bridge would be
    /// painted on top of it. The editor passes the full range and draws it all at
    /// once.
    static func drawTrack(
        walk: WalkResult, width: Double, gateSeams: [Int], transform t: Transform,
        heightRange: ClosedRange<Double> = -1...2,
        into context: inout GraphicsContext
    ) {
        // Every piece is a width-varying RIBBON POLYGON: half-width at each
        // sample follows the height there (Elevation.scale), so a ramp widens
        // as it climbs and the deck is naturally wider — one formula, no
        // ground/deck/ramp special cases. Draw lowest height first so a bridge
        // paints over the road beneath it; equal heights keep walk order.
        let ordered = walk.placed.enumerated()
            .filter { heightRange.contains(max($0.element.entryHeight, $0.element.exitHeight)) }
            .sorted { a, b in
                let ha = a.element.entryHeight + a.element.exitHeight
                let hb = b.element.entryHeight + b.element.exitHeight
                return ha != hb ? ha < hb : a.offset < b.offset
            }
        // Two passes: ALL shadows first, then ALL road surfaces. Otherwise an
        // elevated piece's offset shadow lands on a neighbor's already-drawn
        // road (e.g. the down-ramp getting a dark smear from the deck's
        // shadow). Shadows under everything; surfaces on top, low-to-high.
        for (_, placed) in ordered {
            drawPieceShadow(placed, width: width, t: t, into: &context)
        }
        // Edge decoration (the white line, and kerbs where a corner earns one)
        // goes down BEFORE any asphalt, for two reasons that are really one:
        // asphalt painted over it *is* the clipping rule — a kerb can never
        // cover a neighboring piece's road, because that road is drawn after —
        // and two kerb bands that overlap merge into one shared band instead of
        // fighting over the same strip with clashing dash phases.
        // Kerbs are worked out from the CORNERS, not per piece: the apex kerb
        // and the run-wide exit kerb straddle piece boundaries (see `KerbPlan`).
        let kerbs = KerbPlan.plan(for: walk)
        drawAllEdges(
            walk: walk, kerbs: kerbs, width: width, t: t, heightRange: heightRange,
            into: &context)
        for (_, placed) in ordered {
            drawPieceRibbon(placed, width: width, t: t, into: &context)
        }
        // Checkpoint gates across the seams the author marked (seam 0 is the
        // start/finish, drawn as its own line below).
        for seam in gateSeams where seam != 0 && seam < walk.placed.count {
            let piece = walk.placed[seam]
            guard heightRange.contains(piece.entryHeight) else { continue }
            drawGate(piece, width: width, transform: t, into: &context)
        }

        // Grid-slot markings, then the start/finish line at the start piece's
        // exit (the line paints over the hashes).
        if let start = walk.placed.first(where: { $0.id == PieceCatalog.startPieceID }),
            heightRange.contains(start.exitHeight)
        {
            drawGridMarkings(start, width: width, transform: t, into: &context)
            drawStartLine(start, width: width, transform: t, into: &context)
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
        // Extend the FILL a hair past both end cuts, along each edge's own
        // direction, so abutting pieces' fills overlap sub-pixel and the
        // antialiased seam shows no hairline gap between pieces.
        let fillLeft = extendEnds(e.left, by: 0.6)
        let fillRight = extendEnds(e.right, by: 0.6)
        var outline = Path()
        outline.addLines(fillLeft + fillRight.reversed())
        outline.closeSubpath()

        let elevated = Track.isOffGround(placed.entryHeight) || Track.isOffGround(placed.exitHeight)
        fillRoad(outline, placed: placed, samples: e.samples, t: t, into: &context)
        // Only the DECK's guard rails are drawn on top of the road: they're real
        // barriers, not paint, so they belong over the surface. Ground edge
        // decoration went down in the earlier pass, under all asphalt.
        if elevated {
            strokeDeckRails(left: e.left, right: e.right, t: t, into: &context)
        }
    }

    /// The elevated piece's drop shadow — offset scales with the height at each
    /// point, so a ramp casts a growing shadow (near-zero at the ground end,
    /// full at the deck). Drawn in a pass BEFORE any road surface so it never
    /// smears onto a neighboring piece's road.
    private static func drawPieceShadow(
        _ placed: PlacedPiece, width: Double, t: Transform,
        into context: inout GraphicsContext
    ) {
        guard Track.isOffGround(placed.entryHeight) || Track.isOffGround(placed.exitHeight),
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
    struct Ribbon {
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
    static func edges(_ placed: PlacedPiece, width: Double, t: Transform) -> Ribbon? {
        // Finer than the default 6°: the kerb's stripes are dashed along this
        // polyline, and coarse vertices give the dash pattern corners to catch
        // on (a visible tilt where a boundary lands on one).
        let samples = placed.heightedSamples(degreesPerSample: 2)
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

    /// The deck's guard rails — real barriers, not paint, so unlike ground edge
    /// decoration they're drawn ON TOP of the road surface. Open polylines, so
    /// the piece's entry/exit cuts carry no line and adjacent rails join
    /// seamlessly; ends extend a hair past the cut so a big screen shows no
    /// hairline gap at the joint.
    private static func strokeDeckRails(
        left: [CGPoint], right: [CGPoint], t: Transform,
        into context: inout GraphicsContext
    ) {
        var rails = Path()
        for side in [extendEnds(left, by: 0.6), extendEnds(right, by: 0.6)] {
            guard let first = side.first else { continue }
            rails.move(to: first)
            side.dropFirst().forEach { rails.addLine(to: $0) }
        }
        let band = max(2, 12 * t.scale)
        context.stroke(
            rails, with: .color(.black.opacity(0.5)),
            style: StrokeStyle(lineWidth: band + 5, lineCap: .butt, lineJoin: .round))
        context.stroke(
            rails, with: .color(bridgeRail),
            style: StrokeStyle(lineWidth: band + 2, lineCap: .butt, lineJoin: .round))
    }

    private static func offset(_ p: CGPoint, by s: CGSize) -> CGPoint {
        CGPoint(x: p.x + s.width, y: p.y + s.height)
    }

    /// Push a polyline's two endpoints outward along its own end direction by
    /// `d` screen points — so a filled ribbon overlaps its neighbor by a hair
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

    private static let deckGray = Color(white: 0.72)

    /// Fill the road surface: flat pieces solid (deck lighter), a ramp shaded
    /// dark(ground)→light(deck) so the slope reads.
    private static func fillRoad(
        _ outline: Path, placed: PlacedPiece,
        samples: [(point: Vec2, height: Double)], t: Transform,
        into context: inout GraphicsContext
    ) {
        guard placed.piece.heightDelta != 0 else {
            let elevated = Track.isOffGround(placed.entryHeight)
            context.fill(outline, with: .color(elevated ? deckGray : asphalt))
            return
        }
        let colors = placed.piece.heightDelta > 0 ? [asphalt, deckGray] : [deckGray, asphalt]
        context.fill(
            outline,
            with: .linearGradient(
                Gradient(colors: colors),
                startPoint: t.screen(samples.first!.point), endPoint: t.screen(samples.last!.point))
        )
    }

}
