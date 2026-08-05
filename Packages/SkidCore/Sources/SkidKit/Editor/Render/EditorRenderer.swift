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
    static let bridgeRail = Color(red: 0.55, green: 0.78, blue: 0.95)
    /// Warning-marking yellow: the road-paint amber, warm enough to separate from
    /// the white lines at a glance without going orange-red like the kerbs.
    static let arrowYellow = Color(red: 0.98, green: 0.76, blue: 0.09)

    /// Screen radius of a loose-end tap dot.
    static let endHitRadius: CGFloat = 26

    static func draw(
        walk: WalkResult, width: Double, selectedEnd: Int?, gateSeams: [Int] = [],
        gating: Bool = false, selectedPiece: Int? = nil, decals: [Int: Decal] = [:],
        railed: Set<Int> = [], blockedPieces: Set<Int> = [], showLevels: Bool = false,
        dimmedExcept: Int? = nil, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        // The size limit, made visible. Under everything else, since it's a
        // boundary you build inside of.
        drawCanvasBounds(walk: walk, t: t, into: &context)
        drawTrack(
            walk: walk, width: width, gateSeams: gateSeams, gating: gating, decals: decals,
            railed: railed, transform: t, into: &context)
        // Above ALL road, so a higher deck cannot paint out a lower piece's badge.
        // Blocked pieces are always flagged; the level numbers are a mode, since on a
        // flat track they are noise.
        // Working on one storey: veil the others so the road you are NOT editing is
        // still visible — hiding it would make the map lie about where the track is.
        if let dimmedExcept {
            drawOtherStoreyVeil(walk: walk, keeping: dimmedExcept, t: t, into: &context)
        }
        if showLevels || !blockedPieces.isEmpty {
            drawLevelBadges(
                walk: walk, blockedPieces: blockedPieces, transform: t, into: &context)
        }
        // Over the road, under the end markers: the selected piece is a thing you
        // act on, so it should read on top of the asphalt but not hide the chrome.
        if let selectedPiece, walk.placed.indices.contains(selectedPiece) {
            drawSelection(walk.placed[selectedPiece], width: width, t: t, into: &context)
        }

        // Loose (unbuilt) ends get a construction treatment. That's every
        // walk openEnd, PLUS the HEAD of the chain whenever the loop isn't
        // closed — the origin is an inlet the walk can close onto rather than a
        // loose end, so it never appears in `openEnds`, but it is an open stub
        // until something connects to it (and, since prepend, somewhere you can
        // build).
        //
        // The head is piece 0's entry, not the START piece's: the start line is
        // an ordinary piece that may sit anywhere on the ring, so keying off it
        // drew the stub mid-chain on any track that doesn't begin with it.
        // Each end carries the HEIGHT of the piece it belongs to, so its hazard bar is
        // drawn at the road's own width there. `openEnds` is bare poses, so the height
        // comes from whichever piece the pose sits on.
        var looseEnds = walk.openEnds.map { end -> (pose: PiecePose, height: Double) in
            (end, heightOfEnd(end, in: walk))
        }
        if !walk.openEnds.isEmpty, let first = walk.placed.first {
            // Facing OUT of the piece (back down the road).
            looseEnds.append(
                (
                    PiecePose(
                        position: first.entry.position, heading: first.entry.heading.reversed),
                    first.entryHeight
                ))
        }
        for (i, end) in looseEnds.enumerated() {
            drawLooseEnd(
                end.pose, width: width, height: end.height, selected: i == selectedEnd, t: t,
                into: &context)
        }
    }

    /// One piece's paint, laid immediately after its own asphalt: on top of it (so
    /// it isn't clipped away, the way edge decoration deliberately is), but under
    /// anything drawn later — which is what keeps a decal on the road under a bridge
    /// from ending up on the bridge.
    private static func drawDecal(
        _ decal: Decal?, on placed: PlacedPiece, width: Double, t: Transform,
        into context: inout GraphicsContext
    ) {
        switch decal {
        case .directionArrow:
            drawDirectionArrow(placed, width: width, transform: t, into: &context)
        case .warningArrow:
            drawDirectionArrow(
                placed, width: width, paint: arrowYellow, transform: t, into: &context)
        case nil:
            break
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
        walk: WalkResult, width: Double, gateSeams: [Int], gating: Bool = false,
        decals: [Int: Decal] = [:], railed: Set<Int> = [], transform t: Transform,
        heightRange: ClosedRange<Double> = Track.everyStorey,
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
        // Asphalt then its own paint, PIECE BY PIECE in height order — not all the
        // ribbons and then all the decals. Drawing the decals in a second sweep put
        // a ground road's arrow on top of the bridge that crosses over it, because
        // the deck's asphalt had already been laid. (The race view bands by storey
        // so it never saw this; the editor draws every height in one pass.)
        for (index, placed) in ordered {
            drawPieceRibbon(
                placed, width: width, railed: railed.contains(index), t: t, into: &context)
            drawDecal(decals[index], on: placed, width: width, t: t, into: &context)
            // The start line and grid hashes are paint on the START piece's own
            // road, so they belong to that piece too. Drawn after every ribbon
            // instead, they sat on top of a deck crossing over the start line —
            // the same fault the decals had.
            if placed.id == PieceCatalog.startPieceID {
                drawGridMarkings(placed, width: width, transform: t, into: &context)
                drawStartLine(placed, width: width, transform: t, into: &context)
            }
        }
        // Checkpoint gates across the seams the author marked, skipping the
        // START LINE's own seam — that one is drawn as the start/finish line
        // below. It is the start PIECE's index, not seam 0: the start line is an
        // ordinary piece and may sit anywhere on the ring, so hardcoding 0 drew a
        // checkpoint chevron across the start line and left the real seam 0 bare.
        // Seam N is piece N's EXIT — drawing at the entry put every marker one
        // piece early, which showed the moment the race view (whose white chrome
        // comes from the compiled gates, correctly placed) drew both.
        let startSeam = walk.placed.firstIndex { $0.id == PieceCatalog.startPieceID }
        // In gate mode, show every seam that COULD be gated as a faint candidate,
        // so the author sees what is tappable instead of guessing. Under the real
        // gates, which draw over them.
        if gating {
            let gated = Set(gateSeams)
            for (seam, piece) in walk.placed.enumerated()
            where seam != startSeam && !gated.contains(seam)
                && heightRange.contains(piece.exitHeight)
            {
                drawGateCandidate(piece, width: width, transform: t, into: &context)
            }
        }
        for seam in gateSeams where seam != startSeam && seam < walk.placed.count {
            let piece = walk.placed[seam]
            guard heightRange.contains(piece.exitHeight) else { continue }
            drawGate(piece, width: width, highlighted: gating, transform: t, into: &context)
        }

    }

    /// Draw ONE piece as a width-varying ribbon: at each centerline sample the
    /// half-width scales with the height there (`Elevation.scale`), so a ramp
    /// is a true wedge (narrow at the ground, wide at the deck) and the deck is
    /// wider than the ground — all from one height formula. An elevated stretch
    /// gets a drop shadow + light-blue guardrail; the ground gets the red/white
    /// kerb. Filled polygons (not stroked centerlines), so joints never gap.
    private static func drawPieceRibbon(
        _ placed: PlacedPiece, width: Double, railed: Bool, t: Transform,
        into context: inout GraphicsContext
    ) {
        guard let e = edges(placed, width: width, t: t) else { return }
        // Extend the FILL past both end cuts, along each edge's own direction,
        // so abutting pieces overlap and the antialiased seam shows no hairline
        // gap. See `seamOverlap` for the size.
        let overlap = seamOverlap / t.contextScale
        let fillLeft = extendEnds(e.left, by: overlap)
        let fillRight = extendEnds(e.right, by: overlap)
        var outline = Path()
        outline.addLines(fillLeft + fillRight.reversed())
        outline.closeSubpath()

        // **The railing is drawn where the author put one**, not wherever the road
        // is high: a bridge may have an open edge and a flat piece may be railed.
        // Rails go down FIRST, straddling the edges, and the asphalt then covers
        // their inner half — the same sandwich the ground's kerbs use, which is
        // what puts the two decorations in the same place.
        if railed {
            strokeDeckRails(left: e.left, right: e.right, t: t, into: &context)
        }
        fillRoad(outline, placed: placed, samples: e.samples, t: t, into: &context)
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
        let overlap = seamOverlap / t.contextScale
        for side in [extendEnds(left, by: overlap), extendEnds(right, by: overlap)] {
            guard let first = side.first else { continue }
            rails.move(to: first)
            side.dropFirst().forEach { rails.addLine(to: $0) }
        }
        // Sits exactly where a kerb sits: `kerbBand` wide, straddling the road
        // edge at DOUBLE that width so the asphalt pass covers the inner half
        // and only the outboard half shows. Rails used to be a fixed 12-unit
        // band laid ON the surface, so a bridge's drivable width read narrower
        // than the same road on the ground and the two didn't line up.
        let band = max(3, Double(PieceCatalog.kerbBand) * 2 * t.scale)
        context.stroke(
            rails, with: .color(.black.opacity(0.28)),
            style: StrokeStyle(lineWidth: band + 2, lineCap: .butt, lineJoin: .round))
        context.stroke(
            rails, with: .color(bridgeRail),
            style: StrokeStyle(lineWidth: band, lineCap: .butt, lineJoin: .round))
    }

    private static func offset(_ p: CGPoint, by s: CGSize) -> CGPoint {
        CGPoint(x: p.x + s.width, y: p.y + s.height)
    }

    /// Push a polyline's two endpoints outward along its own end direction by
    /// `d` screen points — so a filled ribbon overlaps its neighbor by a hair
    /// and the antialiased seam shows no background hairline.
    /// How far a piece's fill and rails reach past their end cuts, in SCREEN
    /// points, so abutting pieces overlap instead of leaving a hairline.
    ///
    /// A full point, not the 0.6 this started at: hairlines were still visible
    /// on a 13 mini, worst at the two-piece ramp's mid-climb seam, where both
    /// halves are height-shaded so the gap reads against a gradient rather than
    /// flat grey. A device pixel is 0.33pt at 3× and 0.5pt at 2×, but
    /// antialiasing spreads a diagonal seam over about a point either side, so
    /// the overlap has to clear that — not just one pixel. It costs nothing
    /// visually: the overlap is inside the neighbouring piece's own fill.
    ///
    /// This is in screen points: `edges` returns `Transform.screen` output
    /// (so editor zoom doesn't shrink it), and use sites divide by
    /// `Transform.contextScale` for callers whose context scales further
    /// (the race view — see `contextScale`).
    static let seamOverlap: CGFloat = 1

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
        // Shade follows HEIGHT, at both ends of every piece — not a binary
        // ground/deck pick from the entry. A half-climb blends from its entry
        // shade to its exit shade, and a road resting at 0.5 takes the matching
        // mid shade, so a split climb reads as one continuous surface instead
        // of banding at each seam.
        guard placed.climb != 0 else {
            context.fill(outline, with: .color(roadShade(at: placed.entryHeight)))
            return
        }
        context.fill(
            outline,
            with: .linearGradient(
                Gradient(colors: [
                    roadShade(at: placed.entryHeight), roadShade(at: placed.exitHeight),
                ]),
                startPoint: t.screen(samples.first!.point), endPoint: t.screen(samples.last!.point))
        )
    }

    /// Ground asphalt at the bottom storey, lightest at the top one, blended
    /// between — so height reads as brightness at EVERY level.
    ///
    /// This used to divide by `levelHeight` and clamp at 1, which meant the shade
    /// topped out at the first deck: with three storeys, heights 1, 2 and 3 were
    /// all the same gray and the only cue left was the car's size. Spanning the
    /// world's actual range keeps each storey distinguishable however many there
    /// are, and is unchanged for a two-level track (0…1 spans the same 0…1).
    private static func roadShade(at height: Double) -> Color {
        Color(white: roadShadeWhite(at: height))
    }

    /// The shade's white value, exposed so a test can assert the storeys are
    /// distinguishable without reading pixels.
    static func roadShadeWhite(at height: Double) -> Double {
        let span = Double(Track.highestLevel - Track.lowestLevel) * Track.levelHeight
        let above = height - Double(Track.lowestLevel) * Track.levelHeight
        let f = span > 0 ? min(1, max(0, above / span)) : 0
        // The spread is 0.10 per LEVEL rather than across the whole world, so
        // adding storeys keeps each one as distinguishable as ground-vs-deck was
        // instead of dividing one narrow band ever more finely (three storeys
        // would have been 0.033 apart, which reads as one gray).
        let levels = max(1.0, span / Track.levelHeight)
        return 0.62 + 0.10 * levels * f
    }

    /// The brightest a road gets, so callers that need the range agree with the
    /// shading rather than guessing it.
    static var roadShadeCeiling: Double {
        let levels = max(
            1.0,
            Double(Track.highestLevel - Track.lowestLevel))
        return 0.62 + 0.10 * levels
    }

}
