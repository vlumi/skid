import Foundation

/// **Which road is this?** — the centerline lookups, where 2D position plus a
/// height resolves to a stretch of road. The height part is what keeps a bridge
/// and the road beneath it apart, so read `closestCenterlinePoint`'s notes
/// before changing any of it.
extension Track {
    /// Distance from `p` to the centerline loop — optionally only the road at
    /// roughly `height`, so a bridge and the road beneath it stay distinct.
    public func distanceToCenterline(
        _ p: Vec2, height: Double? = nil, heightTolerance: Double = Self.surfaceTolerance
    ) -> Double {
        var best = Double.greatestFiniteMagnitude
        for i in centerline.indices {
            if let height, !segment(i, isAt: height, tolerance: heightTolerance) { continue }
            let a = centerline[i]
            let b = centerline[(i + 1) % centerline.count]
            best = min(best, p.distance(toSegment: a, b))
        }
        return best
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
        var best = (segment: 0, t: 0.0)
        var bestScore = Double.greatestFiniteMagnitude
        for i in centerline.indices {
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
            if score < bestScore {
                bestScore = score
                let length = (b - a).length
                let t = length > 0 ? (closest - a).length / length : 0
                best = (i, t)
            }
        }
        return best
    }
}
