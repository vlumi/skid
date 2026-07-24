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
        if centerline.count > 1, centerline.first == centerline.last {
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

        return Track(
            id: id,
            centerline: centerline,
            width: Double(PieceCatalog.width),
            elevatedSegments: elevated,
            ramps: ramps,
            gates: gates,
            startSlots: slots,
            startHeading: heading,
            size: TrackValidator.canvas)
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
        let side = fwd.perpendicular * (Double(PieceCatalog.width) / 2)
        return Gate(from: pos - side, to: pos + side, forward: fwd, layer: layer)
    }

    // MARK: - Start grid

    /// Four grid slots ON the start piece, measured back from the start/finish
    /// line at its exit, pole first, staggered left/right, all facing the drive
    /// direction. The start piece is a straight ≥ 300, so the whole grid
    /// (~220 deep) stays on the ribbon behind the line.
    private static func startGrid(at start: PlacedPiece) -> (slots: [Vec2], heading: Double) {
        let line = start.exits[0].position.vec2  // start/finish is at the exit
        let dir = Vec2(angle: start.entry.heading.radians)
        let inward = dir.perpendicular
        let back = 70.0, gap = 50.0, lateral = 28.0
        let slots = (0..<4).map { slot in
            line - dir * (back + Double(slot) * gap)
                + inward * (slot % 2 == 0 ? lateral : -lateral)
        }
        return (slots, start.entry.heading.radians)
    }
}
