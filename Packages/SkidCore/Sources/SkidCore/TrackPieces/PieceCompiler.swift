import Foundation

/// Compiles a saveable `TrackLayout` into the runtime `Track` — **Phase A**:
/// rings + crossings + jumps, onto today's single closed centerline. (Forks
/// need a multi-route `Track`; that's Phase B, and the compiler rejects fork
/// pieces until then.)
///
/// No `TrackDesign` detour — this lands straight on `Track`, alongside the
/// free-form path. Coordinates lower to `Vec2` here and only here.
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

        let road = lowerPieces(walk.placed)
        var centerline = road.centerline
        let elevated = road.elevated
        let rampSegs = road.rampSegs
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
        }

        // Gates: the road cross-section at each marked seam, seams ascending.
        // Runtime convention: the LAST gate is start/finish. Seam 0 is the
        // start line, so emit the others first and seam 0 last.
        let orderedSeams = layout.gateSeams.filter { $0 != 0 }.sorted() + [0]
        for seam in orderedSeams {
            gates.append(gate(at: seam, in: walk.placed))
        }

        let (slots, heading) = startGrid(at: walk.placed[0])

        // Frame the track on what it ACTUALLY occupies, not on the whole
        // allowance.
        //
        // `Track.size` is the renderer's letterbox: it fits `size` to the screen
        // and centers on `size / 2`. Reporting the full canvas here meant every
        // piece-built track was drawn at the scale of the largest *permitted*
        // track and centered on the canvas rather than on itself — so a 1200×960
        // oval rendered small and shoved off to one side, with part of it off
        // screen. Built-in tracks never showed this because a `TrackDesign`
        // carries a hand-authored `size` that matches its layout.
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
            elevatedSegments: elevated,
            rampSegments: rampSegs,
            ramps: ramps,
            walls: walls,
            gates: gates,
            startSlots: slots,
            startHeading: heading,
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
            Ramp(
                from: ramp.a + shift, to: ramp.b + shift, forward: ramp.forward,
                fromLayer: ramp.fromLayer, toLayer: ramp.toLayer, launches: ramp.launches)
        }
        framed.gates = track.gates.map { gate in
            Gate(
                from: gate.a + shift, to: gate.b + shift, forward: gate.forward,
                layer: gate.layer)
        }
        framed.walls =
            track.walls.map { wall in
                Wall(from: wall.a + shift, to: wall.b + shift, layer: wall.layer)
            }
            // The fence goes on AFTER re-framing, since it's defined against the
            // final `size` rather than against the walked coordinates.
            + boundaryWalls(size: bounds.size)
        framed.startSlots = track.startSlots.map { $0 + shift }
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

    // MARK: - Ramps & gates

    /// A ramp/jump line across the road at a piece's entry, in driving
    /// direction, carrying the layer transition (or a launch).
    /// Everything the placed pieces lower to, before gates and re-framing.
    private struct Road {
        var centerline: [Vec2] = []
        /// Segments fully up on the deck.
        var elevated: Set<Int> = []
        /// Segments on a slope, which belong to BOTH layers.
        var rampSegs: Set<Int> = []
        var ramps: [Ramp] = []
        var walls: [Wall] = []
    }

    /// Walk the placed pieces in order, emitting centerline points and the
    /// per-segment sets that describe elevation. Each piece contributes points
    /// from (but not including) its entry — the previous piece's exit — so the
    /// loop isn't double-stamped at seams.
    private static func lowerPieces(_ placed: [PlacedPiece]) -> Road {
        var road = Road()
        guard let first = placed.first else { return road }
        // The very first point is the start piece's entry.
        road.centerline.append(first.entry.position.vec2)

        for piece in placed {
            let before = road.centerline.count - 1  // this piece's entry point
            appendSamples(of: piece, into: &road.centerline)
            let after = road.centerline.count - 1  // this piece's exit point

            // Segments [before ..< after] belong to this piece. A flat piece
            // fully up on the deck (entry & exit both at height 1) is elevated
            // in the runtime Track.
            if piece.piece.heightDelta == 0 && piece.entryHeight > 0.5 {
                for segment in before..<after { road.elevated.insert(segment) }
            }

            // Guard rails along both edges of anything off the ground — the
            // barrier the editor draws as the blue deck rail. Without these a
            // bridge has nothing to stop you driving straight off the side; the
            // only thing catching you was `Race.applyRamps`' fall-off check,
            // which is the *consequence* of leaving the deck, not a wall.
            if piece.entryHeight > 0.5 || piece.exitHeight > 0.5 {
                road.walls.append(contentsOf: deckRails(of: piece))
            }

            // A ramp/jump piece (changes height, or launches) emits a Ramp
            // line, and marks its road as sloped.
            if piece.piece.heightDelta != 0 || piece.piece.launches {
                road.ramps.append(rampLine(at: piece))
                // The sloped road ITSELF, which the runtime needs to know about:
                // `isOnRamp` and `visualHeight` both scan `rampSegments`, so
                // without this a climbing car is never treated as between layers
                // (no smooth growth, no drawing above the deck) and the renderer
                // draws no ramp at all.
                for segment in before..<after { road.rampSegs.insert(segment) }
            }
        }
        return road
    }

    /// The layer-switch line for a ramp piece, at the ramp's **high end**.
    ///
    /// Position matters enormously, because crossing this line flips the car's
    /// discrete layer instantly. Putting it at the ramp's ENTRY meant the car
    /// became "on the deck" the moment it touched the bottom of the ramp — while
    /// still physically at ground level, a road-length away from the deck. Two
    /// visible symptoms followed: the car appeared to jump at the start of the
    /// ramp, and then, being on layer 1 but nowhere near the deck's centerline,
    /// the fall-off check in `applyRamps` dropped it straight back to the
    /// ground — so it drove *under* the bridge and missed the gate up there.
    /// Only enough speed to clear both checks in one tick got you up.
    ///
    /// At the high end, the flip happens exactly where the sloped road meets the
    /// deck, which is what `fromLayer`/`toLayer` describe. A launch (jump) piece
    /// is the exception: it throws the car ballistically from its lip, so its
    /// line belongs at the take-off point — the exit it launches from.
    private static func rampLine(at placed: PlacedPiece) -> Ramp {
        // The high end: a climb switches at its exit, a descent at its entry —
        // in both cases the end that touches the deck.
        let climbing = placed.piece.heightDelta > 0
        let pose = climbing || placed.piece.launches ? placed.exits[0] : placed.entry
        let pos = pose.position.vec2
        let fwd = Vec2(angle: pose.heading.radians)
        let side = fwd.perpendicular * (Double(PieceCatalog.width) / 2)
        // The runtime Track's Ramp still speaks discrete layers; derive them
        // from the piece's entry/exit height.
        let from = Int(placed.entryHeight.rounded())
        let to = Int(placed.exitHeight.rounded())
        return Ramp(
            from: pos - side, to: pos + side, forward: fwd,
            fromLayer: from, toLayer: to, launches: placed.piece.launches)
    }

    /// The road cross-section (a span of `width`) at a seam, as a Gate. Seam N
    /// is the entry pose of piece N — except **seam 0, the start/finish line,
    /// sits at the start piece's EXIT** (where the grid lines up behind it).
    private static func gate(at seam: Int, in placed: [PlacedPiece]) -> Gate {
        let pose: PiecePose
        let layer: Int
        if seam == 0 {
            pose = placed[0].exits[0]
            layer = Int(placed[0].exitHeight.rounded())
        } else {
            let p = placed[seam % placed.count]
            pose = p.entry
            layer = Int(p.entryHeight.rounded())
        }
        let pos = pose.position.vec2
        let fwd = Vec2(angle: pose.heading.radians)
        // A gate spans the whole CORRIDOR, not just the asphalt: running wide
        // onto the grass still counts (the grass is its own penalty), only a
        // gross cut through the infield misses. Each side reaches out
        // independently, capped at HALFWAY to any other lane so a gate can
        // never be satisfied from a neighboring road.
        let half = Double(PieceCatalog.width) / 2
        let side = fwd.perpendicular
        let opposite = Vec2(-side.x, -side.y)
        let inner = pos + opposite * reach(from: pos, along: opposite, half: half, placed: placed)
        let outer = pos + side * reach(from: pos, along: side, half: half, placed: placed)
        return Gate(from: inner, to: outer, forward: fwd, layer: layer)
    }

    /// How far a gate may extend to one side: the road's half-width plus a
    /// margin of grass, but never past halfway to another lane.
    private static func reach(
        from pos: Vec2, along direction: Vec2, half: Double, placed: [PlacedPiece]
    ) -> Double {
        // The grass margin a wide car may still be caught in — generous enough
        // that running wide counts, short of the infield.
        let margin = Double(PieceCatalog.width)
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
