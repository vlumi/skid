import Foundation

/// **Which road is this?** — the centerline lookups, where 2D position plus a
/// height resolves to a stretch of road. The height part is what keeps a bridge
/// and the road beneath it apart, so read `closestCenterlinePoint`'s notes
/// before changing any of it.
extension Track {
    /// Distance from `p` to the centerline loop — optionally only the road at
    /// roughly `height`, so a bridge and the road beneath it stay distinct.
    ///
    /// **A jump's gap is not road.** Its segments are skipped, so a car over the
    /// gap is as far from asphalt as one over grass. That is what makes falling in
    /// possible at all, and it lands here rather than in each caller because this
    /// is the one function every "am I on the road" question goes through.
    ///
    /// **The result can be effectively unbounded** — `greatestFiniteMagnitude` when
    /// NO segment qualifies, which a jump made reachable in normal play (a car in
    /// mid-air over the gap, where the gap skip and the height filter between them
    /// reject everything). Comparing it is fine, which is what every caller here
    /// does; converting it is not. `Int(_:)` traps on it, and did — it crashed the
    /// debug overlay's "off road N" readout.
    public func distanceToCenterline(
        _ p: Vec2, height: Double? = nil, heightTolerance: Double = Self.surfaceTolerance
    ) -> Double {
        // **Only the segments that could be the answer** — the index searches
        // outward by cell ring, so this touches a handful instead of all ~300
        // (measured: this and `surface(at:)` on top of it were the largest single
        // cost in the sim tick, which ran 4.8 ms against a 16.7 ms frame).
        //
        // **Exact, not approximate.** The result is used two ways: every sim
        // caller compares it against a half-width, but the debug overlay PRINTS
        // the magnitude, so "further than I looked" is not an acceptable answer.
        // The ring search therefore keeps going until the nearest hit is provably
        // closer than the next ring can reach — the same value the full scan
        // gives, found without visiting the whole track.
        let index = segmentIndex
        // The gap rules make a segment's contribution more than plain distance,
        // so gapped tracks keep the exhaustive path: they are rare, and being
        // wrong at a gap edge is what lets a car drive on air.
        guard !gaps.contains(true) else {
            return nearestSegmentDistance(
                to: p, over: Array(centerline.indices), height: height,
                heightTolerance: heightTolerance)
        }
        guard
            let nearest = index.nearest(
                to: p, centerline: centerline,
                accept: { i in
                    guard let height else { return true }
                    return segment(i, isAt: height, tolerance: heightTolerance)
                })
        else { return .greatestFiniteMagnitude }
        return nearest.distance
    }

    /// The shared body of `distanceToCenterline`, over whichever segments the
    /// caller decided are worth testing.
    private func nearestSegmentDistance(
        to p: Vec2, over candidates: [Int], height: Double?, heightTolerance: Double
    ) -> Double {
        var best = Double.greatestFiniteMagnitude
        let count = centerline.count
        // **The gap work is skipped entirely on a track with no gaps**, which is
        // almost all of them. This is the hottest loop in the sim — every car asks
        // it several times a tick — and doing three `segmentIsGap` lookups per
        // segment made it 2.7× slower (0.086 → 0.230 ms on the clover's 351
        // points), which at nine cars was most of a 16.7 ms frame.
        let anyGaps = gaps.contains(true)
        for i in candidates {
            if let height, !segment(i, isAt: height, tolerance: heightTolerance) { continue }
            let a = centerline[i]
            let b = centerline[(i + 1) % count]
            guard anyGaps else {
                best = min(best, p.distance(toSegment: a, b))
                continue
            }
            if segmentIsGap(i) { continue }
            // **Asphalt does not overhang a gap.** Distance-to-segment clamps at the
            // endpoints, so a segment's end cap bulges a half-width PAST the last
            // solid point — which paves the first 60 units of any gap from each
            // side, and paves a short gap over entirely. Where a segment ends at a
            // gap it is cut off square instead, which is what a road edge looks like
            // and what lets a car actually drop off one.
            let cutStart = segmentIsGap((i - 1 + count) % count)
            let cutEnd = segmentIsGap((i + 1) % count)
            best = min(best, distance(from: p, toSegment: a, b, squareAt: (cutStart, cutEnd)))
        }
        return best
    }

    /// Distance from `p` to segment `a`–`b`, with either end optionally cut SQUARE
    /// rather than capped: past a square end the segment simply does not exist, so
    /// nothing beyond it counts as road.
    private func distance(
        from p: Vec2, toSegment a: Vec2, _ b: Vec2, squareAt cut: (start: Bool, end: Bool)
    ) -> Double {
        guard cut.start || cut.end else { return p.distance(toSegment: a, b) }
        let along = b - a
        let lengthSquared = along.dot(along)
        guard lengthSquared > 1e-9 else { return p.distance(to: a) }
        let t = (p - a).dot(along) / lengthSquared
        if cut.start, t < 0 { return .greatestFiniteMagnitude }
        if cut.end, t > 1 { return .greatestFiniteMagnitude }
        return p.distance(toSegment: a, b)
    }

    /// Whether `distanceToCenterline` found any road at all. False means "nothing
    /// at that height anywhere" — mid-air over a jump's gap, most commonly — and is
    /// the guard to use before doing arithmetic on the result.
    ///
    /// `isFinite` does NOT work for this: the no-match value is
    /// `greatestFiniteMagnitude`, which is finite. That mistake shipped a crash.
    public static func foundRoad(_ distance: Double) -> Bool {
        distance < .greatestFiniteMagnitude
    }

    /// The closest point on the centerline loop to `p`, as (segment index,
    /// parameter along it). `preferHeight` breaks the tie where two stretches of
    /// road overlap in 2D (a bridge crossing): anchor to the car's own height.
    ///
    /// **The penalty is flat, which looks alarming mid-ramp and isn't.** A ramp's
    /// climb is eased, so partway up no nearby segment matches the car's height,
    /// every candidate takes the penalty, and the nearest road can lose (probed on
    /// the clover: a car at h 0 where the road is 0.392 resolved to a segment 41
    /// units away at 0.098).
    ///
    /// It converges rather than persisting — the car's height moves toward the too
    /// low target, which puts it nearer the real road, which resolves better next
    /// tick. From that same worst case it reached the correct 0.392 in six ticks;
    /// over a full AI lap `surface(at:)` never reported grass while on asphalt.
    /// So don't "fix" it from a static probe. A car placed there abruptly (respawn,
    /// or a start line at a half height) would settle visibly over those ticks; if
    /// that is ever reported, scale the penalty by the height difference.
    /// **`preferHeading` disambiguates an AT-GRADE crossing**, where the height
    /// tiebreak has nothing to work with: both roads are at the same level, so a
    /// car in the shared zone is equally close to a stretch running across its
    /// path. Pass the car's own heading and the road it is actually on wins,
    /// because a legal crossing meets steeply by construction
    /// (`RoadProximity.minCrossingAngle`) — the wrong road is far off the car's
    /// travel, and its penalty is proportional to how far.
    ///
    /// Measured without it, on the eight flattened to one level: `arcPosition`
    /// jumped 1606 units in a single tick — half the lap — as the resolver
    /// flipped to the crossing road. Laps survived (gates are directional) but
    /// standings would swing wildly. Unlike the mid-ramp case above this does
    /// not self-correct, since a crossing is a place the car drives through
    /// every lap.
    public func closestCenterlinePoint(
        to p: Vec2, preferHeight: Double? = nil, preferHeading: Double? = nil
    ) -> (segment: Int, t: Double) {
        // **The index cannot simply replace this scan.** It buckets segments by
        // the area each one COVERS; this function asks which segment scores best
        // ANYWHERE, and the two differ — a point 248 units off the road sits in a
        // cell some segment reaches while the nearest segment lives in the next
        // cell, and the `preferHeading` penalty can favour a segment no nearby
        // cell contains. Both were caught by comparing against the scan, and this
        // answer feeds `arcPosition`, so being wrong swings the standings.
        //
        // **Bounding it by the index was tried and MEASURED SLOWER — 42 µs to
        // 328 µs — so this stays a full scan.** The reasoning was sound (both
        // penalties are bounded by `width`, so once the nearest segment is known
        // every possible winner lies within `nearest + 2 * width`), but a road
        // 120 units wide makes that radius 240: two cell rings in every
        // direction, on top of a ring search to find `nearest` at all, plus the
        // uniquing a multi-cell gather needs. That is more work than testing 300
        // segments with no allocation.
        //
        // The lesson for anything similar: an index pays when the query's answer
        // is LOCAL, and this query's answer is only local in distance, not in
        // score. `distanceToCenterline` and `isOnRamp` — pure proximity, radius
        // known up front — are indexed and did get faster.
        var best = Candidate()
        for i in centerline.indices {
            score(
                segment: i, at: p, preferHeight: preferHeight,
                preferHeading: preferHeading, into: &best)
        }
        return (best.segment, best.t)
    }

    /// The running winner of `closestCenterlinePoint`'s search.
    private struct Candidate {
        var segment = 0
        var t = 0.0
        var score = Double.greatestFiniteMagnitude
    }

    /// Score one segment for `closestCenterlinePoint` and keep it if it wins.
    private func score(
        segment i: Int, at p: Vec2, preferHeight: Double?, preferHeading: Double?,
        into best: inout Candidate
    ) {
        let a = centerline[i]
        let b = centerline[(i + 1) % centerline.count]
        let closest = p.closestPoint(onSegment: a, b)
        var score = p.distance(to: closest)
        if let preferHeight, !segment(i, isAt: preferHeight) {
            score += width  // road at another height loses ties decisively
        }
        if let preferHeading {
            // Undirected: driving a stretch either way is driving that
            // stretch, so only the LINE's alignment matters. Scaled by the
            // road width so a perpendicular road pays about what a
            // wrong-height road pays, and an aligned one pays nothing.
            let along = b - a
            if along.length > 0 {
                let travel = Vec2(angle: preferHeading)
                let alignment = abs(along.normalized.dot(travel))
                score += width * (1 - alignment)
            }
        }
        guard score < best.score else { return }
        let length = (b - a).length
        best = Candidate(
            segment: i, t: length > 0 ? (closest - a).length / length : 0, score: score)
    }
}
