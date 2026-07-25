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
    let maxPieces: Int

    /// Pieces the search may use: plain drivable road only — no start piece
    /// (exactly one per track), no forks/crossings/jumps (each carries rules of
    /// its own), no ramps (they change height).
    private let candidates: [(id: PieceID, piece: Piece)]
    /// Centreline samples of pavement a new run must avoid. The pieces at each
    /// END of the existing chain are legitimately adjacent to the run (it starts
    /// at one and finishes at the other), so they're excluded — otherwise every
    /// candidate is rejected for touching its own neighbours.
    private let existing: [(point: Vec2, height: Double)]
    private let clearanceSquared: Double
    /// The furthest a single piece can carry the road, for pruning runs that can
    /// no longer reach home.
    private let reach: Double

    init(layout: TrackLayout, goal: PiecePose, maxPieces: Int) {
        self.layout = layout
        self.goal = goal
        self.maxPieces = maxPieces
        let placed = layout.walk().placed
        // Ramps are offered only when the road is currently ELEVATED — it then
        // has to come down before the ring can close, and a ramp is the only
        // piece that does that. On the ground they'd just build a bridge to
        // nowhere, so they stay out.
        let elevated = (placed.last?.exitHeight ?? 0) > 0.5
        candidates =
            PieceCatalog.all
            .filter { $0.key != PieceCatalog.startPieceID && $0.value.kind == .road }
            .filter { elevated ? $0.value.heightDelta <= 0 : $0.value.heightDelta == 0 }
            .filter { !$0.value.launches }
            .map { (id: $0.key, piece: $0.value) }
            .sorted { (Self.cost($0.piece), $0.id) < (Self.cost($1.piece), $1.id) }
        existing = placed.dropFirst().dropLast(1).flatMap { piece in
            TrackValidator.samplePoints(piece).map { (point: $0, height: piece.entryHeight) }
        }
        let clearance = Double(PieceCatalog.width) * 0.95
        clearanceSquared = clearance * clearance
        reach = candidates.reduce(0) { longest, entry in
            max(longest, entry.piece.paths[0].exit(from: .origin).position.vec2.length)
        }
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
    private struct Step {
        var pose: PiecePose
        var height: Double
        var run: [PieceID]
        var cost: Int
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
        case found([PieceID])
        /// No run found within `searched` pieces. This is NOT proof that none
        /// exists: the search also gives up when every continuation would touch
        /// pavement already laid, which happens routinely near the loose end
        /// itself. So the editor must never phrase this as "impossible".
        case needsMorePieces(searched: Int)
    }

    func search(from end: PiecePose, height: Double = 0) -> Outcome {
        if end == goal, abs(height) < 0.001 { return .found([]) }
        var frontier = [Step(pose: end, height: height, run: [], cost: 0)]
        var seen: Set<Visited> = [Visited(pose: end, heightStep: Int(height.rounded()))]
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
    private func extend(
        _ step: Step, into next: inout [Step], best: inout Step?, seen: inout Set<Visited>,
        remaining: Int
    ) {
        for (id, piece) in candidates {
            let pose = piece.paths[0].exit(from: step.pose)
            let height = step.height + piece.heightDelta
            // Height must stay in range — nothing climbs above the deck or digs
            // below the ground, and it has to be back at 0 to close.
            guard height >= -0.001, height <= 1.001 else { continue }
            let candidate = Step(
                pose: pose, height: height, run: step.run + [id],
                cost: step.cost + Self.cost(piece))
            let placed = PlacedPiece(
                id: id, piece: piece, entry: step.pose, exits: [pose],
                entryHeight: step.height, entrySeam: 0)
            // Only pavement at the SAME height can be in the way — that's what
            // makes a bridge legal.
            guard staysClear(placed, at: height) else { continue }
            if pose == goal && abs(height) < 0.001 {
                // Keep looking at this depth for a gentler run of the same
                // length — the first hit isn't always the tidiest.
                if best.map({ candidate.cost < $0.cost }) ?? true { best = candidate }
                continue
            }
            let visited = Visited(pose: pose, heightStep: Int(height.rounded()))
            guard !seen.contains(visited) else { continue }
            // Prune what can no longer get home: if the goal is further than the
            // remaining pieces could carry the road, nothing downstream closes.
            guard (goal.position.vec2 - pose.position.vec2).length <= reach * Double(remaining)
            else { continue }
            seen.insert(visited)
            next.append(candidate)
        }
    }

    /// Does a piece placed here stay clear of pavement already laid *at the same
    /// height*? Different heights pass freely — that's a bridge.
    private func staysClear(_ placed: PlacedPiece, at height: Double) -> Bool {
        for point in placed.centerlineSamples(degreesPerSample: 45) {
            for other in existing
            where abs(other.height - height) < 0.5
                && (point - other.point).lengthSquared < clearanceSquared
            {
                return false
            }
        }
        return true
    }

    /// The local clearance test is an approximation, so the winning run goes
    /// through the real validator before it's offered. Height must come home
    /// too: a run that closes the ring while still on the deck isn't a closure.
    private func confirmed(_ run: [PieceID]) -> Bool {
        var candidate = layout
        candidate.pieces += run
        let problems = TrackValidator.validate(candidate).problems
        if problems.contains(.overlap) { return false }
        return !problems.contains {
            if case .unclosedHeight = $0 { return true } else { return false }
        }
    }
}

/// Why a closing search came back without an answer — so the editor can say
/// "needs more than N pieces" instead of staying silent.
public enum ClosureOutcome: Equatable, Sendable {
    case found([PieceID])
    /// No run found within `searched` pieces — which is NOT proof that none
    /// exists (the search also stops when every continuation would touch
    /// pavement already laid). Phrase it as a limit, never as "impossible".
    case needsMorePieces(searched: Int)
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
        case .needsMorePieces(let searched): return .needsMorePieces(searched: searched)
        }
    }

    /// The closing run if one was found within `maxPieces`, else nil.
    public func closingRun(
        from end: PiecePose, to target: PiecePose? = nil, maxPieces: Int = 4
    ) -> [PieceID]? {
        guard case .found(let run) = closingOutcome(from: end, to: target, maxPieces: maxPieces)
        else { return nil }
        return run
    }
}
