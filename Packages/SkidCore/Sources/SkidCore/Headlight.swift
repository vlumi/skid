import Foundation

/// **The headlight cones: two fans of rays, born already clipped.**
///
/// The first attempt at a headlight was a fixed cone shape clipped after the fact, and
/// the clipping is where it died: clipped against storey polygons it vanished at ramp
/// edges, and walls were never in the clip set at all, so it shone straight through
/// them. This is the other construction — each ray is independently *shortened* at the
/// nearest thing that blocks it, and the polygon is just those endpoints joined in
/// order. There is no subtraction step to get wrong, and shine-through is structurally
/// impossible: any ray crossing a wall gets cut.
///
/// **What stops the car stops its light.** The occluders are the sim's own
/// `track.walls`, filtered by the same `Wall.stops(car:)` the collision uses — so a
/// rail on the car's level blocks, a deck rail passes the ground car's light under the
/// bridge, and a ramp's embankment blocks from outside but not from the road it
/// carries. Road is never an input, which is what lets the beam run up a ramp ahead:
/// there is simply no wall across a mouth you may drive into. Anything future that
/// blocks cars — buildings, barriers — occludes light with no new code here.
///
/// **A lamp shoved into a wall goes dark.** Collision stops the car's CENTER from
/// crossing a wall, but the body around it can overlap — and a lamp past the wall line
/// casts rays that never meet the wall at all, which put the light on the far side of a
/// wall the car was pressed against. So each lamp first checks the segment from the
/// center to itself: if a blocking wall crosses it, the lamp is inside the wall and
/// its fan is empty. The center is the one point the sim guarantees stays legal, which
/// is what makes it the anchor.
///
/// The one exception road makes: a deck a full level above the beam *covers* it (the
/// bridge's shadow), so rays stop at a covering deck's edge. Without that cut, the
/// beam — drawn above every road band so the ramp ahead cannot paint over it — would
/// land on top of the bridge instead of under it.
///
/// **Short on purpose.** The cones' job is to make the car's facing readable, not to
/// illuminate: shorter than the car itself, together a bit wider at the tips, drawn in
/// the player's color. Two lamps rather than one center cone, so the light reads as
/// headlights and not as a stray wedge floating at the nose.
public enum Headlight {
    /// How far the light reaches past the nose. Under a car length: it is a facing
    /// cue, not a beam.
    public static let reach = CarGeometry.length * 0.85
    /// Each lamp's sideways offset from the nose center — where the old lamp dots sat.
    public static let lampOffset = CarGeometry.width * 0.17
    /// Half of one lamp's fan at full reach, sized so the pair's outer edge lands a
    /// bit wider than the car's own half-width.
    public static let lampHalfWidth = CarGeometry.width * 0.65 - lampOffset
    /// One lamp's half-angle, derived so its tip lands at `lampHalfWidth`.
    public static var halfAngle: Double { atan2(lampHalfWidth, reach) }
    /// Rays across one lamp's fan. At this reach the gap between neighbouring ray tips
    /// is near a unit, so a wall tip's shadow is sharp to within that.
    public static let rayCount = 16

    /// A deck this far above the beam covers it — the same clearance rule the
    /// under-bridge car windows use, and for the same reason: a curved ramp climbs
    /// half a level over its own footprint, and a genuine deck sits a whole one up.
    static let deckClearance = Track.levelHeight - 0.001
    /// Step between covering-deck samples along a ray. The cut lands within this of
    /// the deck's true edge — at a 29-unit reach, a five-sample ray.
    static let coverSampleStep = 6.0

    /// **The lit fans for a car**, one closed polygon per lamp: the lamp, then one
    /// point per ray — or empty for a lamp buried in a wall. `scale` is the elevation
    /// scale the car itself is drawn at, so the light grows with its car on a climb.
    public static func fans(car: CarState, track: Track, scale: Double = 1) -> [[Vec2]] {
        let direction = Vec2(cos(car.heading), sin(car.heading))
        let sideways = Vec2(-direction.y, direction.x)
        let nose = car.position + direction * (CarGeometry.length / 2 * scale)
        let range = reach * scale

        // Occluders once per car, not per ray. Walls: only visible structures — the
        // map boundary and the level seals are enforced but never drawn, and light
        // dying at a line drawn as nothing reads as a bug. Culled to the lamps' reach.
        let walls = track.walls.filter { wall in
            (wall.kind == .rail || wall.kind == .embankment)
                && wall.stops(car: car, movedFrom: car.position)
                && nose.distance(toSegment: wall.a, wall.b) <= range + lampOffset * scale
        }
        // Covering decks: centerline segments a full level above the beam whose
        // footprint could reach it. Usually empty, so the per-ray sampling below
        // costs nothing on a flat track.
        let covers = track.centerline.indices.filter { index in
            let roadHeight = track.height(ofSegment: index)
            guard roadHeight > car.height + deckClearance else { return false }
            let a = track.centerline[index]
            let b = track.centerline[(index + 1) % track.centerline.count]
            let reachOut = track.footprintHalfWidth(atHeight: roadHeight) + range
            return nose.distance(toSegment: a, b) <= reachOut
        }

        let blockers = Blockers(walls: walls, covers: covers)
        return [-1.0, 1.0].map { side in
            fan(
                from: nose + sideways * (side * lampOffset * scale), of: car,
                range: range, blockers: blockers, track: track)
        }
    }

    /// The occluders gathered once per car: the walls that stop it, and the deck
    /// segments that cover its beam.
    private struct Blockers {
        var walls: [Wall]
        var covers: [Int]
    }

    /// One lamp's fan — or nothing, when the lamp itself is past a wall.
    private static func fan(
        from lamp: Vec2, of car: CarState, range: Double,
        blockers: Blockers, track: Track
    ) -> [Vec2] {
        let walls = blockers.walls
        let covers = blockers.covers
        let anchor = car.position  // the sim keeps the center legal; the body can overlap
        let toLamp = lamp - anchor
        let lampDistance = toLamp.length
        for wall in walls {
            if let hit = intersect(
                from: anchor, direction: toLamp * (1 / lampDistance), a: wall.a, b: wall.b),
                hit <= lampDistance
            {
                return []  // the lamp is inside the wall — dark, not shining beyond it
            }
        }

        var points = [lamp]
        for ray in 0..<rayCount {
            let angle =
                car.heading - halfAngle
                + 2 * halfAngle * Double(ray) / Double(rayCount - 1)
            let rayDirection = Vec2(cos(angle), sin(angle))
            var tip = range
            for wall in walls {
                if let hit = intersect(from: lamp, direction: rayDirection, a: wall.a, b: wall.b),
                    hit < tip
                {
                    tip = hit
                }
            }
            tip = cutAtCoveringDeck(
                from: lamp, direction: rayDirection, limit: tip, covers: covers,
                track: track)
            points.append(lamp + rayDirection * tip)
        }
        return points
    }

    /// Distance along the ray to the segment, or nil when they miss.
    static func intersect(from: Vec2, direction: Vec2, a: Vec2, b: Vec2) -> Double? {
        let edge = b - a
        let denominator = direction.cross(edge)
        guard abs(denominator) > 1e-12 else { return nil }  // parallel
        let offset = a - from
        let along = offset.cross(edge) / denominator
        let across = offset.cross(direction) / denominator
        guard along > 0, across >= 0, across <= 1 else { return nil }
        return along
    }

    /// Shorten the ray at the first sample under a covering deck. Sampling rather
    /// than exact footprint intersection: the error is under one sample step, the
    /// deck edge is a soft shadow line, and the exact form would be a ray-vs-ribbon
    /// query nothing else needs.
    private static func cutAtCoveringDeck(
        from: Vec2, direction: Vec2, limit: Double, covers: [Int], track: Track
    ) -> Double {
        guard !covers.isEmpty else { return limit }
        var distance = coverSampleStep
        while distance <= limit {
            let point = from + direction * distance
            for index in covers {
                let a = track.centerline[index]
                let b = track.centerline[(index + 1) % track.centerline.count]
                let roadHeight = track.height(ofSegment: index)
                if point.distance(toSegment: a, b)
                    <= track.footprintHalfWidth(atHeight: roadHeight)
                {
                    return distance - coverSampleStep
                }
            }
            distance += coverSampleStep
        }
        return limit
    }
}
