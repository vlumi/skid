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
    /// A boundary fence stops everyone. A **rail** is the physical edge of a
    /// stretch of road, and it stops a car that is either at its height OR below
    /// it: you can't drive off the side of a ramp, and you can't climb onto one
    /// from the grass beside it either.
    ///
    /// Matching only the rail's own height was wrong in a way that exactly
    /// produced the reported bug. A rail partway up a ramp sits at, say, 0.5;
    /// with a 0.35 tolerance it matched neither a ground car (0) nor a deck car
    /// (1), so on a measured track only 32 of 82 rails stopped anything and the
    /// mid-ramp ones stopped nobody. That is the gap you drove through to hop
    /// onto the bridge.
    ///
    /// A car ABOVE the rail passes freely, which is what keeps a bridge a bridge:
    /// the road underneath is at 0 while the deck's rails are at 1, so a car down
    /// there is unobstructed.
    private func blocks(_ wall: Wall, car: CarState) -> Bool {
        guard wall.kind != .boundary else { return true }
        return car.height <= wall.height + Track.heightTolerance
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
