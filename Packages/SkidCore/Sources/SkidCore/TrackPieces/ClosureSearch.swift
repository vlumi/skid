import Foundation

/// Finds the shortest run of catalog pieces that closes an open layout — the
/// editor's "Close it" suggestion. This is the answer to "what cancels my
/// diagonal?": the author doesn't have to reason about √2 bookkeeping, they can
/// take the suggestion.
///
/// Breadth-first over piece sequences, so the first hit is the fewest pieces,
/// preferring gentler shapes among runs of equal length. Exactness is integer
/// pose equality, so a suggestion always really closes.
///
/// **Cost matters here**: the editor asks for a suggestion whenever the layout
/// changes, so the search keeps a one-off snapshot of existing pavement and
/// tests candidates against that, rather than re-validating the whole layout per
/// node (which cost ~1.2s a call and jammed the editor). The winning run is
/// confirmed with the real validator, so "suggestable" still means "buildable".
struct ClosureSearch {
    let layout: TrackLayout
    let goal: PiecePose
    /// The height the ring has to come home to — the layout's baseline, which a
    /// raised track puts off the ground.
    let goalHeight: Double
    let maxPieces: Int

    /// Pieces the search may use: plain drivable road only — no start piece
    /// (exactly one per track), no forks/crossings/jumps (each carries rules of
    /// its own), no ramps (they change height).
    private let candidates: [Candidate]
    /// Pavement a new run must avoid, indexed under the one proximity rule
    /// (`RoadProximity`). The WHOLE chain, ends included: the run legitimately
    /// hugs the chain's end where it launches and the start piece where it
    /// lands, and the arc metric knows that — where the old snapshot simply
    /// dropped the first and last piece, which stopped being enough the moment
    /// a primitive closing run spanned more pieces than that (measured: every
    /// candidate on a real 41-piece design was rejected, so "Close it" never
    /// appeared for a track one 90° from home).
    private let mesh: RoadProximity
    /// Own centerline length per candidate id, for the run's arc bookkeeping.
    private let arcOf: [PieceID: Double]
    /// Densified shape of every candidate at each of the eight headings, from
    /// the origin. Poses live on the exact 45° ring, so these ~250 polylines
    /// are ALL the geometry the search can ever place — a node just translates
    /// one, instead of resampling arcs. (Resampling per node was most of the
    /// search's cost once it genuinely explored.)
    private let shapes: [ShapeKey: [Vec2]]
    /// The furthest a single piece can carry the road, for pruning runs that can
    /// no longer reach home.
    private let reach: Double
    /// Where road may still go without the finished track leaving the fixed
    /// canvas: the existing footprint already pins the window on each axis, so
    /// any pose outside it can be pruned without testing anything else.
    private let window: (low: Vec2, high: Vec2)

    init(layout: TrackLayout, goal: PiecePose, maxPieces: Int) {
        self.layout = layout
        self.goal = goal
        self.goalHeight = layout.originHeight
        self.maxPieces = maxPieces
        let placed = layout.walk().placed
        // Level pieces, the climbing/descending compounds, and BOTH pitched
        // variants of the primitives. A run may need to come down — or up: home
        // is the layout's baseline, and a raised track's loose end can sit
        // below it (drop half a level mid-loop and you must climb back). The
        // per-node height bounds keep everything inside the world's storeys, so
        // offering both directions can't wander out of range.
        let level =
            PieceCatalog.all
            .filter { $0.key != PieceCatalog.startPieceID && $0.value.kind == .road }
            .filter { !$0.value.launches }
        candidates =
            (level.filter { $0.value.heightDelta == 0 }
            .flatMap { entry -> [Candidate] in
                PieceExpansion.isPrimitive(entry.key)
                    ? [
                        Candidate(id: entry.key, piece: entry.value, pitch: .flat),
                        Candidate(id: entry.key, piece: entry.value, pitch: .down),
                        Candidate(id: entry.key, piece: entry.value, pitch: .up),
                    ]
                    : [Candidate(id: entry.key, piece: entry.value, pitch: .flat)]
            }
            + level.filter { $0.value.heightDelta != 0 }
            .map { Candidate(id: $0.key, piece: $0.value, pitch: .flat) })
            .sorted {
                (Self.cost($0.piece), $0.id, $0.pitch.rawValue)
                    < (Self.cost($1.piece), $1.id, $1.pitch.rawValue)
            }
        let gap = placed.last?.exits.first.map {
            $0.position.vec2.distance(to: goal.position.vec2)
        }
        mesh = RoadProximity(placed: placed, joinGap: gap ?? .infinity)
        shapes = Self.originShapes(of: candidates)
        arcOf = shapes.reduce(into: [:]) { arcs, entry in
            guard entry.key.heading == 0 else { return }
            var arc = 0.0
            let points = entry.value
            for step in 1..<max(points.count, 1) {
                arc += points[step].distance(to: points[step - 1])
            }
            arcs[entry.key.id] = arc
        }
        reach = candidates.reduce(0) { longest, entry in
            max(longest, entry.piece.paths[0].exit(from: .origin).position.vec2.length)
        }
        window = Self.canvasWindow(around: placed)
    }

    /// Each candidate sampled once per heading, from the origin.
    private static func originShapes(of candidates: [Candidate]) -> [ShapeKey: [Vec2]] {
        var shapes: [ShapeKey: [Vec2]] = [:]
        for candidate in candidates {
            let (id, piece) = (candidate.id, candidate.piece)
            for heading in 0..<8 {
                let entry = PiecePose(
                    position: PiecePose.origin.position, heading: Heading(heading))
                let placed = PlacedPiece(
                    id: id, piece: piece, entry: entry,
                    exits: [piece.paths[0].exit(from: entry)], entryHeight: 0, entrySeam: 0)
                shapes[ShapeKey(id: id, heading: heading)] = RoadProximity.densified(placed)
            }
        }
        return shapes
    }

    /// The band each axis has left before the finished track outgrows the
    /// canvas, from the existing footprint. Any sample outside it would make
    /// the final track off-canvas, so poses out there are dead ends.
    private static func canvasWindow(around placed: [PlacedPiece]) -> (low: Vec2, high: Vec2) {
        var lowest = Vec2(Double.infinity, Double.infinity)
        var highest = Vec2(-Double.infinity, -Double.infinity)
        for piece in placed {
            for point in TrackValidator.samplePoints(piece) {
                lowest = Vec2(min(lowest.x, point.x), min(lowest.y, point.y))
                highest = Vec2(max(highest.x, point.x), max(highest.y, point.y))
            }
        }
        let room =
            TrackValidator.canvas - Vec2(Double(PieceCatalog.width), Double(PieceCatalog.width))
        return (low: highest - room, high: lowest + room)
    }

    /// Straights are free, arcs cost their sweep — so among equal-length runs
    /// the search prefers what an author would have reached for (a hairpin
    /// "closes" many gaps, but suggesting one is rarely helpful).
    private static func cost(_ piece: Piece) -> Int {
        piece.paths[0].reduce(0) { total, segment in
            switch segment {
            case .straight: return total
            case .arc(_, let eighths, _): return total + eighths
            }
        }
    }

    /// One partial run under consideration. Height is part of the state: a pose
    /// alone can't tell "on the deck" from "on the ground", and the ring only
    /// closes when BOTH match the target (the walk enforces the same rule when
    /// mating, so a run that ignored height would be offered and then refused).
    /// Arc is the run's road laid so far, which is what positions each new
    /// piece along the chain for the proximity rule.
    private struct Step {
        var pose: PiecePose
        var height: Double
        var run: [PlannedPiece]
        var cost: Int
        var arc: Double
    }

    /// Poses are compared with height, so `seen` can't collapse a deck pose onto
    /// the ground pose below it.
    private struct Visited: Hashable {
        var pose: PiecePose
        var heightStep: Int
    }

    /// Why a search came back empty — so the editor can say "not within N
    /// pieces" instead of implying no answer exists.
    enum Outcome: Equatable {
        case found([PlannedPiece])
        /// No run found within `searched` pieces. This is NOT proof that none
        /// exists: the search also gives up when every continuation would touch
        /// pavement already laid, which happens routinely near the loose end
        /// itself. So the editor must never phrase this as "impossible".
        case needsMorePieces(searched: Int)
    }

    func search(from end: PiecePose, height: Double = 0) -> Outcome {
        if end == goal, abs(height - goalHeight) < 0.001 { return .found([]) }
        var frontier = [Step(pose: end, height: height, run: [], cost: 0, arc: 0)]
        var seen: Set<Visited> = [Visited(pose: end, heightStep: Int((height * 2).rounded()))]
        for depth in 0..<maxPieces {
            var next: [Step] = []
            var best: Step?
            for step in frontier {
                extend(step, into: &next, best: &best, seen: &seen, remaining: maxPieces - depth)
            }
            if let best, confirmed(best.run) { return .found(best.run) }
            // A dead frontier ends the search early, but proves nothing: it
            // usually means every continuation grazed existing pavement.
            if next.isEmpty { break }
            frontier = next
        }
        return .needsMorePieces(searched: maxPieces)
    }

    /// Try every candidate piece on `step`, recording goal hits in `best` and
    /// keeping viable continuations in `next`.
    ///
    /// Ordered cheap-to-dear on purpose: pose math, then the dedup/reach/canvas
    /// prunes, and the clearance query only for nodes that survive them — the
    /// clearance is the expensive test, and most nodes never reach it.
    private func extend(
        _ step: Step, into next: inout [Step], best: inout Step?, seen: inout Set<Visited>,
        remaining: Int
    ) {
        for entry in candidates {
            let (id, piece, pitch) = (entry.id, entry.piece, entry.pitch)
            let pose = piece.paths[0].exit(from: step.pose)
            let height = step.height + piece.heightDelta + pitch.delta
            // Height must stay within the world's storeys, and it has to be
            // back at 0 to close. (This is also what keeps descent off the
            // ground: one step below 0 is out of the world.)
            guard Track.withinLevels(height) else { continue }
            let candidate = Step(
                pose: pose, height: height,
                run: step.run + [PlannedPiece(id: id, pitch: pitch)],
                cost: step.cost + Self.cost(piece), arc: step.arc + (arcOf[id] ?? 0))
            if pose == goal && abs(height - goalHeight) < 0.001 {
                // Keep looking at this depth for a gentler run of the same
                // length — the first hit isn't always the tidiest.
                guard best.map({ candidate.cost < $0.cost }) ?? true else { continue }
                guard staysClear(id, piece, pitch: pitch, from: step, to: pose) else {
                    continue
                }
                best = candidate
                continue
            }
            // Half-LEVEL granularity: rounding 0.5 into a whole storey would
            // collapse distinct heights into one visited state.
            let visited = Visited(pose: pose, heightStep: Int((height * 2).rounded()))
            guard !seen.contains(visited) else { continue }
            // Prune what can no longer get home: if the goal is further than the
            // remaining pieces could carry the road, nothing downstream closes.
            guard (goal.position.vec2 - pose.position.vec2).length <= reach * Double(remaining)
            else { continue }
            guard inWindow(id, from: step, to: pose) else { continue }
            guard staysClear(id, piece, pitch: pitch, from: step, to: pose) else { continue }
            seen.insert(visited)
            next.append(candidate)
        }
    }

    /// Would this placement keep the finished track inside the canvas? Any
    /// sample outside the remaining window is a dead end for every continuation.
    private func inWindow(_ id: PieceID, from step: Step, to pose: PiecePose) -> Bool {
        guard let shape = shapes[ShapeKey(id: id, heading: step.pose.heading.step)]
        else { return true }
        let offset = step.pose.position.vec2
        for point in shape {
            let world = point + offset
            guard world.x >= window.low.x, world.x <= window.high.x,
                world.y >= window.low.y, world.y <= window.high.y
            else { return false }
        }
        return true
    }

    /// Does a piece placed here stay clear of pavement already laid *at the same
    /// height*? Different heights pass freely — that's a bridge.
    ///
    /// Same rule as the validator: proximity is legal when near along the road,
    /// with the straight-line rest-of-the-way-home standing in for the road the
    /// run hasn't laid yet (never more than the real thing, so the search is at
    /// worst slightly permissive here — `confirmed` re-checks the winner with
    /// the true geometry).
    private func staysClear(
        _ id: PieceID, _ piece: Piece, pitch: Pitch, from step: Step, to pose: PiecePose
    ) -> Bool {
        guard let shape = shapes[ShapeKey(id: id, heading: step.pose.heading.step)]
        else { return true }
        let exitToGoal = pose.position.vec2.distance(to: goal.position.vec2)
        return !mesh.conflicts(
            shape: shape, at: step.pose.position.vec2,
            run: RunContext(
                arcBefore: step.arc, exitToGoal: exitToGoal,
                entryHeight: step.height, heightDelta: piece.heightDelta + pitch.delta))
    }

    /// The local clearance test is an approximation, so the winning run goes
    /// through the real validator before it's offered. Height must come home
    /// too: a run that closes the ring while still on the deck isn't a closure.
    private func confirmed(_ run: [PlannedPiece]) -> Bool {
        var candidate = layout
        candidate.append(contentsOf: run.flatMap { PieceExpansion.expand($0.id, mode: $0.pitch) })
        let problems = TrackValidator.validate(candidate).problems
        // Everything except the gate rule, which is a separate one-tap step the
        // author does afterwards (and is present on every editor track, so
        // treating it as a blocker would reject every suggestion).
        return !problems.contains { problem in
            if case .gates = problem { return false }
            if case .openEnds = problem { return false }  // the run closes them
            return true
        }
    }
}

/// A piece the search may lay, at a pitch.
private struct Candidate {
    var id: PieceID
    var piece: Piece
    var pitch: Pitch
}

/// One step of a suggested run: which piece, laid at what pitch. What the
/// closure search returns and what applying a suggestion expands.
public struct PlannedPiece: Equatable, Sendable {
    public var id: PieceID
    public var pitch: Pitch

    public init(id: PieceID, pitch: Pitch = .flat) {
        self.id = id
        self.pitch = pitch
    }
}

/// A candidate piece at one of the eight headings — the key the cached origin
/// shapes are stored under.
private struct ShapeKey: Hashable {
    var id: PieceID
    var heading: Int
}

/// Why a closing search came back without an answer — so the editor can say
/// "needs more than N pieces" instead of staying silent.
///
/// A found run is **compounds** — the search's own steps. Whoever applies it
/// expands per piece (`canAppend`/`editorAppendRun` already do), which is also
/// what carries each half-climb's pitch into the layout.
public enum ClosureOutcome: Equatable, Sendable {
    case found([PlannedPiece])
    /// No run found within `searched` pieces — which is NOT proof that none
    /// exists (the search also stops when every continuation would touch
    /// pavement already laid). Phrase it as a limit, never as "impossible".
    case needsMorePieces(searched: Int)
    /// No run of catalog pieces closes the gap, but a single **fitting piece**
    /// does. Only ever offered as a fallback: a standard run closes the loop
    /// EXACTLY, in the quantized ring, with no stored floats — better on every
    /// axis, so a fitter is a concession, not an alternative to weigh.
    case fits(Fitter)
}

extension TrackLayout {
    /// The shortest run of pieces that closes this layout from `end`. See
    /// `ClosureSearch`.
    public func closingOutcome(
        from end: PiecePose, to target: PiecePose? = nil, maxPieces: Int = 4
    ) -> ClosureOutcome {
        let search = ClosureSearch(layout: self, goal: target ?? origin, maxPieces: maxPieces)
        // The run starts at whatever height the loose end sits at — an elevated
        // end has to descend before the ring can close.
        let walked = walk()
        let height =
            walked.placed.first { $0.exits.contains(end) }?.exitHeight
            ?? walked.placed.last?.exitHeight ?? 0
        switch search.search(from: end, height: height) {
        case .found(let run): return .found(run)
        case .needsMorePieces(let searched):
            // Fall back to a fitting piece, which bridges gaps the quantized
            // catalog cannot express — but only where the loose end already sits
            // at the height it must close at, since a fitter is flat.
            let goal = target ?? origin
            if abs(height - originHeight) < 0.001,
                let fitter = fitting(from: end, to: goal)
            {
                return .fits(fitter)
            }
            return .needsMorePieces(searched: searched)
        }
    }

    /// The fitting piece that closes `end` onto `goal`, if one can.
    ///
    /// The gap is measured in the loose end's own frame, which is what the solver
    /// wants: forward along its heading, and to its left. A fitter leaves on the
    /// heading it entered, so the headings must already agree — turning is the
    /// catalog's job, and a gap needing a turn is not a fitter's to fix.
    public func fitting(from end: PiecePose, to goal: PiecePose) -> Fitter? {
        guard end.heading == goal.heading else { return nil }
        let delta = goal.position.vec2 - end.position.vec2
        let forward = Vec2(angle: end.heading.radians)
        let left = Vec2(angle: end.heading.radians - .pi / 2)
        return Fitter.solving(forward: delta.dot(forward), left: delta.dot(left))
    }

    /// The closing run if one was found within `maxPieces`, else nil.
    public func closingRun(
        from end: PiecePose, to target: PiecePose? = nil, maxPieces: Int = 4
    ) -> [PlannedPiece]? {
        guard case .found(let run) = closingOutcome(from: end, to: target, maxPieces: maxPieces)
        else { return nil }
        return run
    }
}
