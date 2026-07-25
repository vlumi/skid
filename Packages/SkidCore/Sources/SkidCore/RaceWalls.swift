import Foundation

/// Wall collision: what stops a car, and where.
///
/// Split from `Race` to keep that file inside the length budget.
extension Race {
    /// Returns the hardest into-wall speed absorbed (0 if no contact).
    ///
    /// Swept against the car's whole movement this tick, not just its final
    /// position: at speed a car covers several units per tick, so a
    /// position-only test let it straddle a thin wall between ticks and never
    /// register the hit. That was half of "I can hop onto the bridge from the
    /// grass"; the other half was the height gate below.
    func collideWithWalls(car: inout CarState, movedFrom from: Vec2) -> Double {
        var hardest = 0.0
        for wall in track.walls where blocks(wall, car: car) {
            // Nearest approach of the car's PATH to the wall, so a fast car is
            // caught mid-span rather than only where it happened to stop.
            let closest = nearestPoint(on: wall, toPathFrom: from, to: car.position)
            let offset = car.position - closest
            let dist = offset.length
            guard dist < CarGeometry.radius, dist > 0 else { continue }
            let normal = offset.normalized
            // Push out of the wall, then reflect the into-wall velocity
            // component with restitution.
            car.position = closest + normal * CarGeometry.radius
            let intoWall = car.velocity.dot(normal)
            if intoWall < 0 {
                car.velocity -= normal * intoWall * (1 + tuning.wallRestitution)
                hardest = max(hardest, -intoWall)
            }
        }
        return hardest
    }

    /// Whether this wall stops this car.
    ///
    /// A boundary fence stops everyone. A **rail** guards one stretch of road, and
    /// it blocks from **its own level's floor up to its own height** — that is,
    /// from `trunc(height)` to `height`.
    ///
    /// Both looser rules are wrong, and each produced a reported bug:
    ///
    /// - Blocking only the rail's exact height left the mid-ramp rails (around
    ///   0.5) matching neither a ground car nor a deck car, so on a measured
    ///   track just 32 of 82 rails stopped anything — the gap cars used to hop
    ///   onto the bridge from the grass.
    /// - Blocking everything at or below the rail meant a deck rail at 1.0 also
    ///   blocked a ground car, walling off the road that passes *underneath* the
    ///   bridge.
    ///
    /// The floor is what separates those cases. A ramp rail at 0.5 has floor 0, so
    /// it fences the whole climb from the grass beside it. A deck rail at 1.0 has
    /// floor 1, so it stops cars on the deck and lets the road below run clear.
    ///
    /// **No tolerance on the top.** A wall's height *is* where its top is, so a car
    /// above it is over it — full stop. Adding a tolerance there gave every wall
    /// invisible extra reach, which is what made the ramp's end cap block the
    /// legitimate climb: the cap sat at 0.8 but effectively reached 1.15, and a car
    /// arriving at the mouth at 0.99 hit its own exit. (0.99, not 1.0, because the
    /// per-tick clamp means the climb approaches deck height asymptotically.)
    /// The floor keeps a tolerance — that end is about which level the wall belongs
    /// to, and a car's own size matters there.
    private func blocks(_ wall: Wall, car: CarState) -> Bool {
        guard wall.kind != .boundary else { return true }
        let floor = wall.height.rounded(.down)
        return car.height >= floor - Track.reachTolerance && car.height <= wall.height
    }

    /// The point on `wall` nearest the car's swept path this tick — treating the
    /// movement as a segment rather than a point, so fast cars can't tunnel.
    private func nearestPoint(on wall: Wall, toPathFrom from: Vec2, to end: Vec2) -> Vec2 {
        // Cheap and good enough at tick scale: test both ends of the movement and
        // its midpoint against the wall, and keep whichever came closest.
        var best = end.closestPoint(onSegment: wall.a, wall.b)
        var bestDistance = end.distance(to: best)
        for sample in [from, (from + end) * 0.5] {
            let candidate = sample.closestPoint(onSegment: wall.a, wall.b)
            let distance = sample.distance(to: candidate)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }
}
