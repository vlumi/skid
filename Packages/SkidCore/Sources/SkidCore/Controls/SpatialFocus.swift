import Foundation

/// Which way an arrow key asks the menu highlight to move.
public enum FocusDirection: Sendable, CaseIterable {
    case up, down, left, right
}

/// **Moving a menu highlight by arrow keys, on any layout** — the way a TV
/// remote moves between tiles, rather than through a list someone has to keep
/// in order. Pure geometry over the buttons' frames, so every screen gets it
/// without being told what its rows and columns are.
public enum SpatialFocus {
    /// The candidate an arrow moves to from `current`, or nil to stay put.
    ///
    /// A candidate must lie ahead in `direction` (its centre past the current
    /// centre). Score = 3 × the side gap (edge to edge across the direction, 0
    /// when overlapping) + the distance ahead: a button straight ahead beats
    /// one at a comparable distance off to the side, yet a near row still
    /// beats a far one that merely lines up. Ties go to the most centred.
    ///
    /// With nothing focused yet, the first press picks the reading-order first
    /// (topmost, then leftmost) whatever its direction: the highlight has to
    /// appear somewhere before it can move.
    public static func next(
        from current: Rect?, among candidates: [Rect], direction: FocusDirection
    ) -> Int? {
        guard !candidates.isEmpty else { return nil }
        guard let current else {
            return candidates.indices.min { a, b in
                let ra = candidates[a], rb = candidates[b]
                return ra.minY != rb.minY ? ra.minY < rb.minY : ra.minX < rb.minX
            }
        }
        var best: (index: Int, score: Double)?
        for (index, candidate) in candidates.enumerated() {
            guard let score = score(of: candidate, from: current, direction: direction) else {
                continue
            }
            if best == nil || score < best!.score { best = (index, score) }
        }
        return best?.index
    }

    /// Lower is better; nil when `candidate` is not ahead in `direction`.
    private static func score(of candidate: Rect, from current: Rect, direction: FocusDirection)
        -> Double?
    {
        let along: Double  // how far ahead, centre to centre
        let gap: Double  // how far off to the side, edge to edge (0 = overlapping)
        let drift: Double  // centre-to-centre offset across, the final tiebreak
        switch direction {
        case .left, .right:
            along = (candidate.center.x - current.center.x) * (direction == .right ? 1 : -1)
            gap = max(0, max(candidate.minY, current.minY) - min(candidate.maxY, current.maxY))
            drift = abs(candidate.center.y - current.center.y)
        case .up, .down:
            along = (candidate.center.y - current.center.y) * (direction == .down ? 1 : -1)
            gap = max(0, max(candidate.minX, current.minX) - min(candidate.maxX, current.maxX))
            drift = abs(candidate.center.x - current.center.x)
        }
        guard along > 0.5 else { return nil }
        return gap * 3 + along + drift * 0.01
    }
}
