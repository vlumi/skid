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
            let reach =
                CarGeometry.radius + outboardThickness(of: wall, approachedFrom: from)
            guard dist < reach, dist > 0 else { continue }
            let normal = offset.normalized
            // Push out of the wall, then reflect the into-wall velocity
            // component with restitution.
            car.position = closest + normal * reach
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
    func blocks(_ wall: Wall, car: CarState) -> Bool {
        switch wall.kind {
        case .boundary:
            return true
        case .gate:
            // One-way level seal: stops what comes from below, and only what
            // comes from the ONE storey below. The gate hangs from its road
            // down to the ground beneath it, not into the earth — a tunnel car
            // a full level further down passes under it exactly like a ground
            // car passes under a deck. No top rule either: a gate isn't a
            // structure with a height a car could clear, it's a threshold
            // ("be of this level, or stay out").
            return car.height < wall.height
                && car.height >= wall.height - Track.levelHeight
        case .rail:
            // Embankment-only trunc: "which level's floor does this rail's
            // guard reach down to" assumes storeys at whole heights ≥ 0. A
            // tunnel cutting's rails are one-way and get their own kind (see
            // docs/height-model-plan.md step 4), so this stays as is.
            let floor = wall.height.rounded(.down)
            return car.height >= floor - Track.reachTolerance && car.height <= wall.height
        }
    }

    /// How far a wall's **structure** stands proud of its collision segment on
    /// the side the car is hitting it from.
    ///
    /// A rail is a segment in the model but a BAND on screen: the renderer
    /// strokes the ribbon's edge `kerbBand` either side, so the asphalt covers
    /// the inner half and `kerbBand` shows outboard. Approached from the grass
    /// the car therefore stopped in mid-air, its centre `CarGeometry.radius`
    /// from a line sitting well inside the visible barrier — measured at a
    /// clover ramp root, a 4.9-unit gap between where the car halted and where
    /// the railing was drawn. From inside there is nothing to add: the band's
    /// inner half is under the asphalt, so the segment already is the face.
    ///
    /// Which side the car is on comes from the wall's stored `outward`, because
    /// it cannot be worked out here: a centerline search costs too much to run
    /// per wall per car per tick (it took the suite from 28 seconds to 533), and
    /// "away from the middle of the map" is a coin flip on a track that curls
    /// back on itself — 192 of 430 clover rails wrong. A wall with no `outward`
    /// (the map boundary, a level seal, a ramp's end cap) has no bulk to stand
    /// clear of and adds nothing.
    private func outboardThickness(of wall: Wall, approachedFrom from: Vec2) -> Double {
        guard wall.kind == .rail, wall.outward.length > 0.001 else { return 0 }
        guard (from - wall.a).dot(wall.outward) > 0 else { return 0 }
        return railThickness(atHeight: wall.height)
    }

    /// How far a rail's band stands outboard of its collision segment, at the
    /// height that rail guards.
    ///
    /// Per rail, not one constant, because the segment does not track the band:
    /// rails are generated at the NOMINAL road edge (deliberately — see
    /// `PieceCompilerWalls.deckRails`, where scaling them per sample made
    /// mid-ramp rails drift outboard) while the band is drawn at the PAINTED
    /// edge, which grows with height. So the gap between line and band grows
    /// too: 15 units at a ground rail, 27 at a deck rail.
    ///
    /// Taking the deck's figure for every rail — the first version of this —
    /// gave the low rails 12 units of reach they are not drawn with, which is
    /// an invisible wall to lean against at a ramp's root. Each rail knows its
    /// own height, so it uses it.
    private func railThickness(atHeight height: Double) -> Double {
        let face = track.halfWidth(atHeight: height) + Double(PieceCatalog.kerbBand)
        return max(0, face - track.width / 2)
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
