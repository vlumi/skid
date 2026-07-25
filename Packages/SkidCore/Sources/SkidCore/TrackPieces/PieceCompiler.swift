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
    private static let degreesPerSample = 6.0

    public static func compile(_ layout: TrackLayout, id: String = "") throws -> Track {
        let validation = TrackValidator.validate(layout)
        guard validation.isSaveable else { throw Failure.notSaveable(validation.problems) }

        let walk = layout.walk()
        guard !walk.placed.contains(where: { $0.piece.kind == .fork }) else {
            throw Failure.forkNotSupportedInPhaseA
        }

        // Walk the placed pieces in order, emitting centerline points. Each
        // piece contributes points from (but not including) its entry — the
        // previous piece's exit — so the loop isn't double-stamped at seams.
        var centerline: [Vec2] = []
        var elevated: Set<Int> = []
        var ramps: [Ramp] = []
        var gates: [Gate] = []

        // The very first point is the start piece's entry.
        centerline.append(walk.placed[0].entry.position.vec2)

        for placed in walk.placed {
            let before = centerline.count - 1  // index of this piece's entry point
            appendSamples(of: placed, into: &centerline)
            let after = centerline.count - 1  // index of this piece's exit point

            // Segments [before ..< after] belong to this piece. A flat piece
            // fully up on the deck (entry & exit both at height 1) is elevated
            // in the runtime Track.
            if placed.piece.heightDelta == 0 && placed.entryHeight > 0.5 {
                for seg in before..<after { elevated.insert(seg) }
            }

            // A ramp/jump piece (changes height, or launches) emits a Ramp
            // line at its entry seam.
            if placed.piece.heightDelta != 0 || placed.piece.launches {
                ramps.append(rampLine(at: placed))
            }
        }

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
            ramps: ramps,
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
        framed.startSlots = track.startSlots.map { $0 + shift }
        framed.size = bounds.size
        // `pit` defaults to the center of whatever `size` was at init, so it has
        // to be re-derived from the new frame rather than shifted.
        framed.pit = bounds.size * 0.5
        return framed
    }

    /// The bounding box of everything the renderer draws, so nothing lands
    /// outside the frame it's told to fit.
    ///
    /// The centerline is padded by half a road plus the outboard decoration (and
    /// the deck's extra width, since an elevated piece is drawn wider). Gate ends
    /// and grid slots are included as points, because a gate deliberately reaches
    /// out over the grass and would otherwise poke through the edge.
    private static func footprint(of centerline: [Vec2], gates: [Gate], slots: [Vec2])
        -> Footprint
    {
        guard !centerline.isEmpty else { return Footprint(origin: .zero, size: Vec2(1, 1)) }
        let half =
            Double(PieceCatalog.width) / 2 * Elevation.scale(atHeight: 1)
            + Double(PieceCatalog.kerbBand)
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for point in centerline {
            minX = min(minX, point.x - half)
            minY = min(minY, point.y - half)
            maxX = max(maxX, point.x + half)
            maxY = max(maxY, point.y + half)
        }
        for point in gates.flatMap({ [$0.a, $0.b] }) + slots {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
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
    private static func rampLine(at placed: PlacedPiece) -> Ramp {
        let pos = placed.entry.position.vec2
        let fwd = Vec2(angle: placed.entry.heading.radians)
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
