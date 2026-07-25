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
    private let existing: [Vec2]
    private let clearanceSquared: Double
    /// The furthest a single piece can carry the road, for pruning runs that can
    /// no longer reach home.
    private let reach: Double

    init(layout: TrackLayout, goal: PiecePose, maxPieces: Int) {
        self.layout = layout
        self.goal = goal
        self.maxPieces = maxPieces
        candidates =
            PieceCatalog.all
            .filter { $0.key != PieceCatalog.startPieceID && $0.value.kind == .road }
            .filter { $0.value.heightDelta == 0 && !$0.value.launches }
            .map { (id: $0.key, piece: $0.value) }
            .sorted { (Self.cost($0.piece), $0.id) < (Self.cost($1.piece), $1.id) }
        let placed = layout.walk().placed
        existing = placed.dropFirst().dropLast(1).flatMap { TrackValidator.samplePoints($0) }
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

    /// One partial run under consideration.
    private struct Step {
        var pose: PiecePose
        var run: [PieceID]
        var cost: Int
    }

    func run(from end: PiecePose) -> [PieceID]? {
        guard end != goal else { return [] }
        var frontier = [Step(pose: end, run: [], cost: 0)]
        var seen: Set<PiecePose> = [end]
        for depth in 0..<maxPieces {
            var next: [Step] = []
            var best: Step?
            for step in frontier {
                extend(step, into: &next, best: &best, seen: &seen, remaining: maxPieces - depth)
            }
            if let best, confirmed(best.run) { return best.run }
            frontier = next
        }
        return nil
    }

    /// Try every candidate piece on `step`, recording goal hits in `best` and
    /// keeping viable continuations in `next`.
    private func extend(
        _ step: Step, into next: inout [Step], best: inout Step?, seen: inout Set<PiecePose>,
        remaining: Int
    ) {
        for (id, piece) in candidates {
            let pose = piece.paths[0].exit(from: step.pose)
            let candidate = Step(
                pose: pose, run: step.run + [id], cost: step.cost + Self.cost(piece))
            let placed = PlacedPiece(
                id: id, piece: piece, entry: step.pose, exits: [pose], entryHeight: 0,
                entrySeam: 0)
            guard staysClear(placed) else { continue }
            if pose == goal {
                // Keep looking at this depth for a gentler run of the same
                // length — the first hit isn't always the tidiest.
                if best.map({ candidate.cost < $0.cost }) ?? true { best = candidate }
                continue
            }
            guard !seen.contains(pose) else { continue }
            // Prune what can no longer get home: if the goal is further than the
            // remaining pieces could carry the road, nothing downstream closes.
            guard (goal.position.vec2 - pose.position.vec2).length <= reach * Double(remaining)
            else { continue }
            seen.insert(pose)
            next.append(candidate)
        }
    }

    /// Does a piece placed here stay clear of pavement already laid?
    private func staysClear(_ placed: PlacedPiece) -> Bool {
        for point in placed.centerlineSamples(degreesPerSample: 45) {
            for other in existing where (point - other).lengthSquared < clearanceSquared {
                return false
            }
        }
        return true
    }

    /// The local clearance test is an approximation, so the winning run goes
    /// through the real validator before it's offered.
    private func confirmed(_ run: [PieceID]) -> Bool {
        var candidate = layout
        candidate.pieces += run
        return !TrackValidator.validate(candidate).problems.contains(.overlap)
    }
}

extension TrackLayout {
    /// The shortest run of pieces that closes this layout from `end`, or nil if
    /// none exists within `maxPieces`. See `ClosureSearch`.
    public func closingRun(
        from end: PiecePose, to target: PiecePose? = nil, maxPieces: Int = 4
    ) -> [PieceID]? {
        ClosureSearch(layout: self, goal: target ?? origin, maxPieces: maxPieces).run(from: end)
    }
}
