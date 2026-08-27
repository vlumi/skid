import Foundation

/// Compiles a saveable `TrackLayout` into the runtime `Track` — **Phase A**:
/// rings + crossings + jumps, onto today's single closed centerline. (Forks
/// need a multi-route `Track`; that's Phase B, and the compiler rejects fork
/// pieces until then.)
///
/// Coordinates lower to `Vec2` here and only here.
public enum PieceCompiler {
    public enum Failure: Error, Equatable {
        case notSaveable([Validation.Problem])
        case forkNotSupportedInPhaseA
    }

    /// Arc sampling density — matches the existing ≤6°/segment convention.
    static let degreesPerSample = 6.0

    /// **Grass around the road, in world units: one road width.** The world's
    /// boundary wall stands at the frame's edge, so this is the run-off a car
    /// has before it hits it — and, since grass is painted exactly over the
    /// world, the breathing room a track shows on screen. It used to be zero:
    /// the frame hugged the outermost kerb, and leaving the road near the
    /// edge meant hitting an invisible wall at once. Fixed rather than per
    /// track on purpose (the codec can grow a field later if a track needs
    /// it); the editor draws this same frame so authors build inside it.
    public static let runOff = Double(PieceCatalog.width)

    /// **The world a layout compiles to, in LAYOUT coordinates** — the rect
    /// the grass will cover and the boundary wall will stand on. For the
    /// editor to draw while building, so it never throws: an unfinished loop
    /// still has a frame, just one that will move as pieces are added.
    public static func worldFrame(_ layout: TrackLayout) -> Rect? {
        let walk = layout.walk()
        guard !walk.placed.isEmpty else { return nil }
        let road = lowerPieces(walk.placed, railed: layout.railed)
        var gates: [Gate] = []
        for seam in layout.gateSeams where walk.placed.indices.contains(seam) {
            gates.append(gate(at: seam, in: walk.placed))
        }
        let start = walk.placed.first { $0.id == PieceCatalog.startPieceID }
        let slots = start.map { startGrid(at: $0).slots } ?? []
        let box = footprint(of: road.centerline, gates: gates, slots: slots)
        return Rect(origin: box.origin, size: box.size)
    }

    public static func compile(_ layout: TrackLayout, id: String = "") throws -> Track {
        let validation = TrackValidator.validate(layout)
        guard validation.isSaveable else { throw Failure.notSaveable(validation.problems) }

        let walk = layout.walk()
        guard !walk.placed.contains(where: { $0.piece.kind == .fork }) else {
            throw Failure.forkNotSupportedInPhaseA
        }

        let road = lowerPieces(walk.placed, railed: layout.railed)
        var centerline = road.centerline
        var heights = road.heights
        var deckTops = road.deckTops
        var gaps = road.gaps
        let ramps = road.ramps
        let walls = road.walls
        var gates: [Gate] = []

        // The centerline is a closed loop; drop the duplicated closing point
        // (last == first by closure) so the runtime's wraparound is clean.
        //
        // Compared with a TOLERANCE, not `==`. Loop closure is exact in the
        // `Coord` ring, but these points have been lowered to `Vec2`, where the
        // last point can miss the first by an ULP or two — leaving a
        // zero-length closing segment that later float work can round into
        // visibility. A hair under a millimetre of road is far below anything
        // geometric and safely above accumulated rounding.
        if centerline.count > 1, let first = centerline.first, let last = centerline.last,
            (last - first).length < 0.001
        {
            centerline.removeLast()
            if heights.count > centerline.count { heights.removeLast() }
            if deckTops.count > centerline.count { deckTops.removeLast() }
            if gaps.count > centerline.count { gaps.removeLast() }
        }

        // Gates: the road cross-section at each marked seam, seams ascending.
        // Runtime convention: the LAST gate is start/finish, and the start/finish
        // line is the START PIECE's own seam — which is its index, since seam N
        // is piece N's exit. It is NOT seam 0: the start line is an ordinary
        // piece and may sit anywhere on the ring (see
        // docs/flexible-tracks-plan.md), so a track can be rotated, and later
        // anchored somewhere other than its start.
        let startSeam =
            walk.placed.firstIndex { $0.id == PieceCatalog.startPieceID } ?? 0
        let orderedSeams = layout.gateSeams.filter { $0 != startSeam }.sorted() + [startSeam]
        for seam in orderedSeams {
            gates.append(gate(at: seam, in: walk.placed))
        }

        let (slots, heading) = startGrid(at: walk.placed[startSeam])

        // Frame the track on what it ACTUALLY occupies, not on the whole
        // allowance.
        //
        // `Track.size` is the renderer's letterbox: it fits `size` to the screen
        // and centers on `size / 2`. Reporting the full canvas here meant every
        // piece-built track was drawn at the scale of the largest *permitted*
        // track and centered on the canvas rather than on itself — so a 1200×960
        // oval rendered small and shoved off to one side, with part of it off
        // screen. The old hand-authored tracks never showed this: their `size`
        // was authored to match their layout.
        //
        // Two halves, both required: measure the real footprint, AND move the
        // geometry so it starts at the origin, since the renderer assumes the
        // world runs 0…size.
        // Gates reach OUTBOARD of the asphalt (running wide onto the grass still
        // counts), so they'd stick out of a frame measured from the road alone.
        let unframed = Track(
            id: id,
            centerline: centerline,
            width: Double(PieceCatalog.width),
            heights: heights,
            deckTops: deckTops,
            gaps: gaps,
            ramps: ramps,
            walls: walls,
            gates: gates,
            layout: layout,
            startSlots: slots,
            startHeading: heading,
            startHeight: layout.originHeight,
            size: TrackValidator.canvas)
        return framed(unframed)
    }

    /// Re-frame a track onto its own footprint: report its true extent as `size`,
    /// and move its geometry to start at the origin.
    private static func framed(_ track: Track) -> Track {
        let bounds = footprint(
            of: track.centerline, gates: track.gates, slots: track.startSlots)
        let shift = Vec2(-bounds.origin.x, -bounds.origin.y)
        var framed = track
        framed.centerline = track.centerline.map { $0 + shift }
        // Only the POSITIONS shift; `forward` is a direction and must not.
        framed.ramps = track.ramps.map { ramp in
            Ramp(from: ramp.a + shift, to: ramp.b + shift, forward: ramp.forward)
        }
        framed.gates = track.gates.map { gate in
            Gate(
                from: gate.a + shift, to: gate.b + shift, forward: gate.forward,
                height: gate.height)
        }
        framed.walls =
            track.walls.map { wall in
                // COPY and move, rather than rebuild field-by-field. The old
                // form listed every field by hand, so anything added to `Wall`
                // was silently dropped here — which cost a session: a new flag
                // reached the walls and vanished at framing, and the walls
                // looked correct everywhere it was set.
                //
                // Only the POSITIONS shift; `outward` is a direction, and
                // nothing else depends on where the wall sits.
                var moved = wall
                moved.a = wall.a + shift
                moved.b = wall.b + shift
                return moved
            }
            // The fence goes on AFTER re-framing, since it's defined against the
            // final `size` rather than against the walked coordinates.
            + boundaryWalls(size: bounds.size)
        framed.startSlots = track.startSlots.map { $0 + shift }
        // Remember the shift, so drawing from the layout can match the geometry.
        framed.layoutOffset = shift
        framed.size = bounds.size
        // `pit` defaults to the center of whatever `size` was at init, so it has
        // to be re-derived from the new frame rather than shifted.
        framed.pit = bounds.size * 0.5
        return framed
    }

    /// The frame to draw the track in: centered on the ROAD, and grown
    /// symmetrically until the chrome fits.
    ///
    /// Centering is the whole point here. The renderer places the map by fitting
    /// this frame to the screen, so whatever is off-center *inside* the frame is
    /// off-center on screen. Measuring the raw bounding box of everything drawn
    /// gets that wrong: gates deliberately reach outboard over the grass, and a
    /// gate on one side only (an oval with a checkpoint on the right straight)
    /// pushed the box out on that side alone — leaving a few pixels of grass on
    /// the left and a visibly bigger band on the right.
    ///
    /// So: take the road's own box (symmetric by construction), then for each
    /// axis find the largest overhang of any gate end or grid slot beyond it, and
    /// add that much to BOTH sides. The chrome still fits, and the road stays
    /// centered.
    private static func footprint(of centerline: [Vec2], gates: [Gate], slots: [Vec2])
        -> Footprint
    {
        guard !centerline.isEmpty else { return Footprint(origin: .zero, size: Vec2(1, 1)) }
        // Half the road, plus the widest thing drawn outboard of it (a deck is
        // wider still — Elevation.scale — so allow for that), plus the run-off.
        let half =
            Double(PieceCatalog.width) / 2 * Elevation.scale(atHeight: 1)
            + Double(PieceCatalog.kerbBand) + runOff
        let xs = centerline.map { $0.x }
        let ys = centerline.map { $0.y }
        var minX = xs.min()! - half
        var maxX = xs.max()! + half
        var minY = ys.min()! - half
        var maxY = ys.max()! + half

        // The chrome's worst overhang on each axis, applied to both sides so the
        // road stays in the middle.
        var padX = 0.0
        var padY = 0.0
        for point in gates.flatMap({ [$0.a, $0.b] }) + slots {
            padX = max(padX, minX - point.x, point.x - maxX)
            padY = max(padY, minY - point.y, point.y - maxY)
        }
        minX -= padX
        maxX += padX
        minY -= padY
        maxY += padY
        return Footprint(
            origin: Vec2(minX, minY), size: Vec2(maxX - minX, maxY - minY))
    }

    /// Where a compiled track sits and how big it is — the two numbers the
    /// renderer's letterbox needs.
    private struct Footprint {
        /// The top-left corner, in the coordinates the walk produced.
        var origin: Vec2
        /// The extent, which becomes `Track.size`.
        var size: Vec2
    }

    // MARK: - Centerline

    /// Append a piece's centerline points AFTER its entry (already present).
    private static func appendSamples(of placed: PlacedPiece, into line: inout [Vec2]) {
        let pts = placed.centerlineSamples(degreesPerSample: degreesPerSample)
        line.append(contentsOf: pts.dropFirst())  // entry already in `line`
    }

    // MARK: - Lowering pieces

    /// Everything the placed pieces lower to, before gates and re-framing.
    private struct Road {
        var centerline: [Vec2] = []
        /// Height per centerline point, parallel to `centerline`.
        var heights: [Double] = []
        /// The TOP of the piece each point belongs to (its highest end),
        /// parallel to `centerline`. This is the height the renderer bins whole
        /// ribbons by, so anything that must stack with the ribbon — a car
        /// mid-climb — can stack by the same rule instead of its raw height.
        var deckTops: [Double] = []
        /// Which points carry no asphalt (a jump's gap), parallel to `centerline`.
        var gaps: [Bool] = []
        /// Jump take-off lines only — an ordinary climb is just `heights`.
        var ramps: [Ramp] = []
        var walls: [Wall] = []
    }

    /// Walk the placed pieces in order, emitting centerline points with their
    /// heights. Each piece contributes points from (but not including) its entry
    /// — the previous piece's exit — so the loop isn't double-stamped at seams.
    ///
    /// Height comes straight from `heightedSamples`, the same smoothstepped
    /// profile the editor draws, so the road a car drives is the road it looked
    /// like while being built.
    private static func lowerPieces(_ placed: [PlacedPiece], railed: Set<Int> = []) -> Road {
        var road = Road()
        guard let first = placed.first else { return road }
        road.centerline.append(first.entry.position.vec2)
        road.heights.append(first.entryHeight)
        road.deckTops.append(max(first.entryHeight, first.exitHeight))
        road.gaps.append(false)

        for (index, piece) in placed.enumerated() {
            let top = max(piece.entryHeight, piece.exitHeight)
            let samples = piece.heightedSamples(degreesPerSample: degreesPerSample)
            let gapSpan = piece.piece.gapSpan
            let last = Double(max(samples.count - 1, 1))
            // **A zero-length piece contributes no road.** A warp moves the road's
            // height without occupying ground, so its samples are all the same point
            // — and emitting them stamped a pile of duplicate centerline points,
            // each casting its own half-width end cap. That paved right over the
            // neighboring gap: the car stayed "on road" across the hole and never
            // took off, which is a launch that silently does nothing.
            //
            // The height still lands, because the walk carries it in `exitHeight`
            // and the next piece starts from there.
            if piece.piece.kind == .warp { continue }
            for (offset, sample) in samples.enumerated().dropFirst() {
                road.centerline.append(sample.point)
                road.heights.append(sample.height)
                road.deckTops.append(top)
                // Samples along a jump are evenly spaced (it is a straight), so
                // the index IS the fraction along the piece.
                road.gaps.append(gapSpan?.contains(Double(offset) / last) ?? false)
            }

            // **Two separate reasons to emit edge walls, and they no longer
            // coincide.** The earth under a climb is structure — without it a car
            // drives into a ramp's flank — so it follows the geometry. A railing is
            // the author's choice, so it follows `railed`, and that is what makes
            // a bridge without railings and a railing on flat ground both
            // expressible.
            let wantsRail = railed.contains(index)
            let climbs = piece.climb != 0
            let elevated =
                Track.isOffGround(piece.entryHeight) || Track.isOffGround(piece.exitHeight)
            if wantsRail || climbs || elevated {
                road.walls.append(
                    contentsOf: deckRails(
                        of: piece, capHighEnd: capsHighEnd(piece), railed: wantsRail))
            }

        }
        return road
    }

    /// The road cross-section (a span of `width`) at a seam, as a Gate.
    ///
    /// **Seam N is the boundary at piece N's EXIT** — uniformly, with no special
    /// case. Seam 0 is therefore the start piece's exit, which is where the
    /// start/finish line and the grid behind it already live, and seam N for every
    /// other piece is the far end of that piece.
    ///
    /// This used to read "piece N's ENTRY, except seam 0 which is the start piece's
    /// exit". Those two rules describe the same boundary for consecutive pieces, so
    /// seam 0 and seam 1 aliased: marking both stacked two gates on the start line
    /// and the runtime scored the lap twice. One rule for every seam removes the
    /// alias by construction rather than by validation.
    private static func gate(at seam: Int, in placed: [PlacedPiece]) -> Gate {
        let piece = placed[seam % placed.count]
        let pose = piece.exits[0]
        let height = piece.exitHeight
        let pos = pose.position.vec2
        let fwd = Vec2(angle: pose.heading.radians)
        // A gate spans the whole CORRIDOR, not just the asphalt: running wide
        // onto the grass still counts (the grass is its own penalty), only a
        // gross cut through the infield misses. Each side reaches out
        // independently, capped at HALFWAY to any other lane so a gate can
        // never be satisfied from a neighboring road.
        // The half-width AT THIS HEIGHT, because the road widens as it rises. A
        // flat `width / 2` made an elevated gate NARROWER than the asphalt it
        // spans — measured on a three-storey track, a level-3 gate covered 63% of
        // its own road (against 248% on the ground, which is the intended grass
        // margin), so running wide up there missed the checkpoint entirely. Same
        // class as the rails that sat inboard of the road; see
        // `Track.halfWidth(atHeight:)`.
        let half = Double(PieceCatalog.width) / 2 * Elevation.scale(atHeight: height)
        let side = fwd.perpendicular
        let opposite = Vec2(-side.x, -side.y)
        let inner = pos + opposite * reach(from: pos, along: opposite, half: half, placed: placed)
        let outer = pos + side * reach(from: pos, along: side, half: half, placed: placed)
        return Gate(from: inner, to: outer, forward: fwd, height: height)
    }

    /// How far a gate may extend to one side: the road's half-width plus a
    /// margin of grass, but never past halfway to another lane.
    private static func reach(
        from pos: Vec2, along direction: Vec2, half: Double, placed: [PlacedPiece]
    ) -> Double {
        // The grass margin a wide car may still be caught in — generous enough
        // that running wide counts, short of the infield. Proportional to the road
        // it edges (`half` is already height-scaled), so a raised gate keeps the
        // same generosity rather than a shrinking share of it.
        let margin = half * 2
        var limit = half + margin
        // Any pavement out this way caps the reach at the midpoint between the
        // two roads, so the corridor can't spill into the neighbor's lane.
        for piece in placed {
            for point in piece.centerlineSamples(degreesPerSample: 20) {
                let offset = point - pos
                let sideways = offset.dot(direction)
                // Only pavement genuinely out to this side, and roughly abreast
                // rather than ahead or behind (that's the same road).
                guard sideways > half else { continue }
                let along = abs(offset.dot(Vec2(-direction.y, direction.x)))
                guard along < half else { continue }
                limit = min(limit, sideways / 2)
            }
        }
        return max(half, limit)
    }

    // MARK: - Start grid

    /// Four grid slots ON the start piece, measured back from the start/finish
    /// line at its exit, pole first, staggered left/right, all facing the drive
    /// direction. The start piece is a 2U straight and the grid is ~220 deep,
    /// so the whole grid stays on the ribbon behind the line (asserted in
    /// tests, since the two numbers must stay compatible).
    private static func startGrid(at start: PlacedPiece) -> (slots: [Vec2], heading: Double) {
        let line = start.exits[0].position.vec2  // start/finish is at the exit
        let dir = Vec2(angle: start.entry.heading.radians)
        return (Grid.positions(line: line, dir: dir), start.entry.heading.radians)
    }
}
