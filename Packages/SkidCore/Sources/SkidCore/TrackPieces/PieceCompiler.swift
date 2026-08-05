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
        // Half the road, plus the widest thing drawn outboard of it. A deck is
        // wider still (Elevation.scale), so allow for that too.
        let half =
            Double(PieceCatalog.width) / 2 * Elevation.scale(atHeight: 1)
            + Double(PieceCatalog.kerbBand)
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

            // Only a LAUNCH needs a line: it throws the car ballistically, which
            // is a real event at a place. An ordinary ramp needs nothing — its
            // climb is in `heights`, and the car follows the road.
            if piece.piece.launches {
                road.ramps.append(launchLine(at: piece))
            }
        }
        return road
    }

    /// The take-off line of a jump: across the road **at the lip**, where the
    /// asphalt ends and the gap begins.
    ///
    /// **At the ENTRY side, not the exit.** A jump's gap opens just after the
    /// piece begins, so a line at the exit sits past the landing — the car fell
    /// into the gap and was thrown only once it had already crossed. (The old
    /// spelling read `exits[0]`, which was harmless while a "jump" was solid road
    /// and the line was merely early or late rather than on the wrong side of the
    /// hole.)
    ///
    /// The span is the **scaled** half-width, so an elevated jump's line still
    /// reaches the edges of its wider drawn road; a flat `width / 2` left a car
    /// near the edge crossing outboard of the line and never launching.
    private static func launchLine(at placed: PlacedPiece) -> Ramp {
        let entry = placed.entry
        let forward = Vec2(angle: entry.heading.radians)
        // Sit at the lip: the fraction where the gap starts, along the piece.
        //
        // INTERPOLATED by distance, not snapped to a sample index. A straight has
        // only its two endpoints, so rounding an index put the line at the piece's
        // entry — a whole unit before the gap on a 4U jump, where the car was thrown
        // while still on solid road.
        let start = placed.piece.gapSpan?.lowerBound ?? 0
        let position = placed.point(atFraction: start) ?? entry.position.vec2
        let height = placed.height(atFraction: start)
        let side =
            forward.perpendicular * (Double(PieceCatalog.width) / 2)
            * Elevation.scale(atHeight: height)
        return Ramp(from: position - side, to: position + side, forward: forward)
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

    /// Where the four grid slots sit relative to the start/finish line: the
    /// pole `back` behind it, each next slot a further `gap` back, staggered
    /// `lateral` to alternating sides. Shared so the renderer paints its hash
    /// marks exactly where the compiler puts the cars.
    public enum Grid {
        public static let back = 70.0
        public static let gap = 50.0
        public static let lateral = 28.0
        public static let slots = 4
        /// How far behind the line the last slot sits — the depth of ribbon the
        /// start piece has to provide.
        public static var depth: Double { back + Double(slots - 1) * gap }

        /// Slot centers, pole first, from the line pose. `dir` is the driving
        /// direction; slots run back from the line, staggered sideways.
        public static func positions(line: Vec2, dir: Vec2) -> [Vec2] {
            let inward = dir.perpendicular
            return (0..<slots).map { slot in
                line - dir * (back + Double(slot) * gap)
                    + inward * (slot % 2 == 0 ? lateral : -lateral)
            }
        }
    }

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
