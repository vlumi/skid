import Foundation

/// Whether a layout is **saveable**, and if not, exactly why — so the editor
/// can explain a loose end rather than just graying out Save. Everything short
/// of saveable is a normal *editing* state, never an error.
public struct Validation: Equatable, Sendable {
    public enum Problem: Equatable, Sendable {
        /// The walk itself broke (unknown piece, empty).
        case walk(WalkResult.Failure)
        /// Loose ends remain — the graph isn't fully connected.
        case openEnds(Int)
        /// Two pieces overlap on the same layer where they may not.
        case overlap
        /// Not exactly one start-grid piece.
        case startCount(Int)
        /// Gates out of range, or the start line's seam not marked, or a route
        /// crosses them
        /// in a different order.
        case gates
        /// The footprint doesn't fit the fixed canvas.
        case offCanvas
        /// The ring closes somewhere other than ground level — it climbed a
        /// ramp and never came back down, so the road would meet itself at two
        /// different heights.
        case unclosedHeight(Double)
        /// The road left the world's storeys — climbed past the top level or
        /// dug below the bottom one.
        case heightOutOfBounds(Double)
        /// A fitting piece has no solved shape, or a shape that doesn't reach
        /// what it is supposed to close onto. Carries how many are wrong.
        case unsolvedFitter(Int)
    }

    public var problems: [Problem]
    public var isSaveable: Bool { problems.isEmpty }

    public init(problems: [Problem] = []) { self.problems = problems }
}

/// Validates a `TrackLayout` against the saveable rules (design doc §Validity).
public enum TrackValidator {
    /// The fixed canvas a layout must fit within (a format-version constant;
    /// the ~1.2:1 taller-aspect convention — tune with the catalog numbers).
    public static let canvas = Vec2(1600, 1333)

    /// Whether appending `id` keeps the layout **buildable** — i.e. it doesn't
    /// pave over itself or leave the canvas. The editor uses this to refuse the
    /// placement outright, which is far better than accepting it and showing a
    /// message the author can miss.
    ///
    /// Deliberately ignores the rules a work-in-progress is *expected* to break:
    /// loose ends, the gate count, and standing on the deck are all normal
    /// mid-build states, not reasons to block a piece.
    /// `id` may be a **compound** (the palette offers one-tap hairpins and 90s);
    /// it is expanded here, because what actually lands in the layout is
    /// primitives, and validating the compound would test a piece the layout will
    /// never hold.
    public static func canAppend(
        _ id: PieceID, pitch: Pitch = .flat, to layout: TrackLayout
    ) -> Bool {
        var candidate = layout
        candidate.append(contentsOf: PieceExpansion.expand(id, mode: pitch))
        return placeable(candidate)
    }

    /// The same verdict for a whole run at once — what "Close it" applies. A
    /// run validated as a unit must also land as a unit; judging it piece by
    /// piece would re-litigate each prefix.
    public static func canAppend(run: [PlannedPiece], to layout: TrackLayout) -> Bool {
        var candidate = layout
        candidate.append(contentsOf: run.flatMap { PieceExpansion.expand($0.id, mode: $0.pitch) })
        return placeable(candidate)
    }

    /// Whether **prepending** `id` keeps the layout buildable — the same verdict
    /// as `canAppend`, at the other end. Expanded to primitives for the same
    /// reason, and prepended in reverse so the expansion still reads forwards
    /// once it is in (see `TrackLayout.prependAll`).
    ///
    /// Also false when the piece has no exact inverse placement, since the model
    /// declines that rather than rounding.
    public static func canPrepend(
        _ id: PieceID, pitch: Pitch = .flat, to layout: TrackLayout
    ) -> Bool {
        var candidate = layout
        guard candidate.prependAll(PieceExpansion.expand(id, mode: pitch)) else { return false }
        return placeable(candidate)
    }

    /// The placement verdict: ignore what a work-in-progress is expected to
    /// break, refuse what can never become a track.
    private static func placeable(_ candidate: TrackLayout) -> Bool {
        !validate(candidate).problems.contains { problem in
            switch problem {
            case .overlap, .offCanvas, .walk, .heightOutOfBounds: return true
            // An unsolved fitter is an ordinary mid-build state — the piece is
            // placed, then solved — so it does not make a placement illegal. It
            // does stop the track saving, which is rule 4b in `validate`.
            case .openEnds, .gates, .startCount, .unclosedHeight, .unsolvedFitter:
                return false
            }
        }
    }

    public static func validate(_ layout: TrackLayout) -> Validation {
        var problems: [Validation.Problem] = []

        let walk = layout.walk()
        if let failure = walk.failure {
            return Validation(problems: [.walk(failure)])  // nothing else is meaningful
        }

        // 1. Every port mated.
        if !walk.openEnds.isEmpty {
            problems.append(.openEnds(walk.openEnds.count))
        }

        // 3. Exactly one start piece.
        let startCount = layout.pieces.filter { $0 == PieceCatalog.startPieceID }.count
        if startCount != 1 {
            problems.append(.startCount(startCount))
        }

        // 2. No disallowed same-layer overlap.
        if hasIllegalOverlap(walk) {
            problems.append(.overlap)
        }

        // 4. Gates: 2…16, the start line's own seam included, in range.
        if !gatesValid(layout, placedCount: walk.placed.count) {
            problems.append(.gates)
        }

        // 4b. Every fitter is solved, and its shape really spans its gap. A
        // fitter's geometry is not in the catalog — it is stored per placement —
        // so an unsolved one has no road at all, and a stale one (its neighbours
        // edited after it was solved) would leave a visible kink at the seam.
        let brokenFitters = unsolvedFitters(layout, walk: walk)
        if brokenFitters > 0 {
            problems.append(.unsolvedFitter(brokenFitters))
        }

        // 5. Fits the canvas.
        if !fitsCanvas(walk.placed) {
            problems.append(.offCanvas)
        }

        // 5b. Stays within the world's storeys. This used to be nobody's rule:
        // the editor's single ramp button auto-picked a legal direction, so
        // nothing ever climbed past the deck or dug below the ground — but the
        // button was the only shield (measured: appending a second climb, or a
        // descent from the ground, validated happily). With pitch on ordinary
        // pieces, every button can climb, so the bound belongs to validation.
        if let escaped = walk.placed.first(where: { !Track.withinLevels($0.exitHeight) }) {
            problems.append(.heightOutOfBounds(escaped.exitHeight))
        }

        // 6. Height comes home. A ring that climbs a ramp must descend before it
        // closes, or the road meets itself at two different heights — a
        // bridge to nowhere. (The walk only compares heights when auto-mating an
        // inlet, so a ring closing onto the origin could sneak through elevated.)
        // Only meaningful once the ring IS closed: mid-build, standing on the
        // deck is exactly what you'd expect.
        // A ring must come home to the height it STARTED at — which is the
        // layout's baseline now, not necessarily the ground: a whole track may
        // sit on the deck.
        if walk.openEnds.isEmpty, let last = walk.placed.last,
            abs(last.exitHeight - layout.originHeight) > 0.001
        {
            problems.append(.unclosedHeight(last.exitHeight))
        }

        return Validation(problems: problems)
    }

    // MARK: - Rule helpers

    /// Seam 0 marked, 2…16 gates, all in range.
    ///
    /// No seam needs excluding any more. Seam numbering used to have a quirk at the
    /// ring's join — seam 0 meant the start piece's *exit* while every other seam N
    /// meant piece N's *entry* — which made seams 0 and 1 the same boundary, so
    /// marking both stacked two gates on the start line and the runtime scored the
    /// lap twice. Seam N now uniformly means piece N's exit, so the alias is gone by
    /// construction and every seam in range is a distinct boundary.
    ///
    /// (The "every route crosses gates in the same cyclic order" rule only bites
    /// once forks compile — Phase B — since Phase A tracks are single-route by
    /// construction.)
    /// How many fitting pieces are missing a shape, or carry one that no longer
    /// spans the gap it has to bridge.
    ///
    /// The second half is what keeps a fitter honest under editing: its shape is
    /// stored, not derived, so moving or deleting a neighbour changes the gap
    /// without changing the stored answer. Checking that the shape still lands on
    /// the piece's own exit catches that, and it is the same comparison the seam
    /// test makes.
    private static func unsolvedFitters(_ layout: TrackLayout, walk: WalkResult) -> Int {
        var wrong = 0
        for placed in walk.placed where placed.id == PieceCatalog.fitterPieceID {
            guard let fitter = placed.fitter else {
                wrong += 1
                continue
            }
            let step = fitter.displacement
            let forward = Vec2(angle: placed.entry.heading.radians)
            let left = Vec2(angle: placed.entry.heading.radians - .pi / 2)
            let reached =
                placed.entry.position.vec2 + forward * step.forward + left * step.left
            if reached.distance(to: placed.exits[0].position.vec2) > fitterTolerance {
                wrong += 1
            }
        }
        return wrong
    }

    /// How far a stored fitter may land from the pose it must reach. Generous
    /// against the solve's own precision (which is four orders finer) and far
    /// below anything visible — a device pixel is about a unit — so this catches
    /// a STALE shape, not a rounding difference.
    private static let fitterTolerance = 0.5

    private static func gatesValid(_ layout: TrackLayout, placedCount: Int) -> Bool {
        let seams = Set(layout.gateSeams)
        // The start line's own seam must be gated — it is the finish line. That
        // seam is the start PIECE's index, not 0: the start line is an ordinary
        // piece that may sit anywhere on the ring, so requiring seam 0 would
        // forbid every rotation of a valid track.
        let startSeam = layout.pieces.firstIndex(of: PieceCatalog.startPieceID) ?? 0
        guard seams.contains(startSeam) else { return false }
        guard (2...16).contains(seams.count) else { return false }
        return layout.gateSeams.allSatisfy { (0..<placedCount).contains($0) }
    }

    /// Sample-level overlap under the one proximity rule (`RoadProximity`):
    /// near in space is illegal only when far along the road, with the join gap
    /// counted as road-to-be. Same-height layers and legal crossings are the
    /// only piece-level exemptions left; everything positional — neighbours
    /// touching at ports, a tight curve crowding itself, the closing corner
    /// hugging the start on its way home — falls out of the arc metric.
    private static func hasIllegalOverlap(_ walk: WalkResult) -> Bool {
        let placed = walk.placed
        let mesh = RoadProximity(
            placed: placed, joinGap: joinGap(walk), isClosed: walk.openEnds.isEmpty)
        // Heights are the mesh's own business now (per-segment solidity — a
        // ramp's two ends are at different levels, so piece-level heights were
        // wrong at one of them). Only the crossing-kind policy stays out here.
        return mesh.hasIllegalPair { i, j in
            legallyCrossing(placed[i], placed[j])
        }
    }

    /// The straight-line gap from the loose end back to the start entry — zero
    /// once the ring is closed (exit and entry coincide exactly), infinite when
    /// there is nothing to close.
    private static func joinGap(_ walk: WalkResult) -> Double {
        guard let first = walk.placed.first, let last = walk.placed.last,
            let exit = last.exits.first
        else { return .infinity }
        return exit.position.vec2.distance(to: first.entry.position.vec2)
    }

    /// A crossable/crossable pair meeting at a shared point, or a jump gap a
    /// road runs under, is a permitted overlap.
    private static func legallyCrossing(_ a: PlacedPiece, _ b: PlacedPiece) -> Bool {
        let kinds = Set([a.piece.kind, b.piece.kind])
        if kinds == [.crossing] { return true }  // two crossables may cross
        if kinds.contains(.jump) { return true }  // a road may pass under a gap
        return false
    }

    private static func fitsCanvas(_ placed: [PlacedPiece]) -> Bool {
        guard !placed.isEmpty else { return false }
        let half = Double(PieceCatalog.width) / 2
        var pts: [Vec2] = []
        for p in placed { pts.append(contentsOf: samplePoints(p)) }
        let minX = pts.map(\.x).min()! - half
        let maxX = pts.map(\.x).max()! + half
        let minY = pts.map(\.y).min()! - half
        let maxY = pts.map(\.y).max()! + half
        return (maxX - minX) <= canvas.x && (maxY - minY) <= canvas.y
    }

    /// Coarse centerline samples of a piece's first path, as world `Vec2`.
    /// Enough for overlap/canvas checks; the compiler samples arcs finely.
    /// Delegates to the shared sampler (which walks segment chains, so a
    /// chicane or jog samples both of its arcs) at a coarse angular step.
    static func samplePoints(_ placed: PlacedPiece) -> [Vec2] {
        placed.centerlineSamples(degreesPerSample: 22.5)
    }

}
