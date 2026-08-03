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
    /// `walls` defaults to the track's own — overridable so a test can put one
    /// barrier in a known place and measure the response, rather than hunting for a
    /// suitable wall on a real track.
    func collideWithWalls(
        car: inout CarState, movedFrom from: Vec2, walls: [Wall]? = nil
    ) -> Double {
        var hardest = 0.0
        // Debug only (see `CarState.WallContact`): what this tick's contact did. The
        // held figures survive between ticks so a screenshot can be read.
        let speedBefore = car.velocity.length
        var held = car.wallContact
        held.hits = 0
        held.press = 0
        held.squareness = 0
        held.slide = 0
        held.speedLost = 0
        car.wallContact = held
        for wall in walls ?? track.walls where blocks(wall, car: car, movedFrom: from) {
            // Nearest approach of the car's PATH to the wall, so a fast car is
            // caught mid-span rather than only where it happened to stop.
            let closest = nearestPoint(on: wall, toPathFrom: from, to: car.position)
            let reach =
                CarGeometry.radius + outboardThickness(of: wall, approachedFrom: from)
            // **Which side the car came FROM decides where it is put back.**
            //
            // Using the direction to where it ENDED UP is wrong the moment a step
            // carries it past the wall: that direction points to the far side, so
            // the push-out shoved it further out. Reported on the flat eight — the
            // car went through the fence and got stuck outside the course.
            //
            // The approach side is the honest answer, and it also handles the
            // crossing case below: a car that swapped sides is put back on the one
            // it started on.
            let crossed = crosses(wall, from: from, to: car.position)
            let approach = sideNormal(of: wall, at: closest, from: from)
            let offset = car.position - closest
            let dist = offset.length
            guard crossed || (dist < reach && dist > 0) else { continue }
            let approachSide = approach.length > 0 ? approach : offset.normalized
            guard approachSide.length > 0 else { continue }
            // Physics resolves against the wall's FACE, not the approach direction:
            // the latter is diagonal on a long wall, and a graze resolved against a
            // slanted normal came off harder than it went in.
            let wallFace = faceNormal(of: wall, towards: approachSide)
            // Remove only the overlap. Assigning `closest + approachSide * reach` is
            // an absolute position recomputed each tick, and `closest` tracks the
            // car's PATH — so a car held against a rail lost ALL its travel, not just
            // the into-wall part (device: glued in place while the overlay read 300+).
            let overlap = reach - (car.position - closest).dot(wallFace)
            if overlap > 0 { car.position += wallFace * overlap }
            let intoWall = car.velocity.dot(wallFace)
            guard intoWall < 0 else { continue }
            respond(car: &car, normal: wallFace, intoWall: intoWall)
            hardest = max(hardest, -intoWall)
            car.wallContact.hits += 1
        }
        // Debug bookkeeping (see `CarState.WallContact`): hold figures across a RUN of
        // contact, because a tick is 1/60 s and no screenshot can be timed to one.
        if car.wallContact.hits > 0 {
            let lost = speedBefore - car.velocity.length
            car.wallContact.speedLost = lost
            if car.wallContact.ticks == 0 {
                car.wallContact.worstLoss = 0
                car.wallContact.totalLoss = 0
                car.wallContact.speedAtStart = speedBefore
            }
            car.wallContact.ticks += 1
            car.wallContact.idleTicks = 0
            car.wallContact.worstLoss = max(car.wallContact.worstLoss, lost)
            car.wallContact.totalLoss += lost
        } else {
            car.wallContact.idleTicks += 1
            // Clear for a third of a second: this run of contact is over.
            if car.wallContact.idleTicks > 20 { car.wallContact.ticks = 0 }
        }
        return hardest
    }

    /// Below this the hit is a pure glance — no square bounce, just scrape and the
    /// subdued glance kick. An arcade car clipping a barrier at 25° should slide
    /// along it, not come off.
    static let glancingAngle = 25.0
    /// At or above this it is a pure head-on, with the full bounce.
    ///
    /// 60°, not 75°: on device only a near-square hit bounced at all, and really bad
    /// cornering deserves punishing. Lowering it means a 60° mistake gets the full
    /// kick and the band 25…60 ramps up through it, so a sloppy apex costs something
    /// visible rather than just scrubbing along.
    static let headOnAngle = 60.0

    /// Remap the approach sine onto 0…1 across the glance→head-on band.
    static func squareness(ofSine sine: Double) -> Double {
        let low = sin(glancingAngle * .pi / 180)
        let high = sin(headOnAngle * .pi / 180)
        guard sine > low else { return 0 }
        guard sine < high else { return 1 }
        let t = (sine - low) / (high - low)
        return t * t * (3 - 2 * t)  // smoothstep, so the band has no hard edges
    }

    /// The wall's own outward face, signed to the side the car is on. Perpendicular
    /// to the wall, unlike the approach direction, so contact is resolved against
    /// the barrier rather than against the line back to where the car came from.
    private func faceNormal(of wall: Wall, towards side: Vec2) -> Vec2 {
        let run = wall.b - wall.a
        guard run.length > 0.001 else { return side }
        let face = run.perpendicular.normalized
        return face.dot(side) >= 0 ? face : face * -1
    }

    /// **What hitting a wall does to the car**, given the into-wall speed.
    ///
    /// Three things, where the old model did only the first:
    ///
    /// - **Bounce**, but scaled by how square the hit is. `restitution` at head-on
    ///   falling to nothing when parallel — reflecting the full normal component at
    ///   every angle is what made a graze kick out instead of scrubbing along, which
    ///   is the reported complaint. Some bounce on a near-head-on hit is wanted and
    ///   stays.
    /// - **Friction along the wall**, proportional to how hard it is pressed. With
    ///   no tangential loss at all, riding a barrier cost nothing and hugging one
    ///   was the fast line. A hard enough graze can take most of the speed out of
    ///   the car, which is what "a wall can stop you" means.
    /// - **Yaw**, pulling the nose parallel. A car with mass pivots along the
    ///   barrier rather than skipping off it, and this is most of what reads as
    ///   weight rather than as a pinball.
    private func respond(car: inout CarState, normal: Vec2, intoWall: Double) {
        let press = -intoWall  // positive: how hard the car is going into the wall
        let along = normal.perpendicular  // unit, since `normal` is
        let slide = car.velocity.dot(along)
        let speed = car.velocity.length
        // **How square the hit is: 0 a glance, 1 head-on.** Not the raw sine of the
        // approach angle — for an arcade game 30° is still very much a glance, and
        // only near-90° is a real head-on. So the sine is remapped through a band:
        // everything under `glancingAngle` reads as a pure glance, everything over
        // `headOnAngle` as a pure head-on, smoothly in between.
        let sine = speed > 0.001 ? min(1, press / speed) : 0
        let squareness = Self.squareness(ofSine: sine)
        // Record the HARDEST contact of the tick, which is the one that matters.
        if press > car.wallContact.press {
            car.wallContact.press = press
            car.wallContact.squareness = squareness
            car.wallContact.slide = slide
        }

        // 1. Bounce, scaled from a subdued glance to full restitution head-on. A
        //    pure glance keeps SOME kick (zero read as flypaper on device) and the
        //    scale never exceeds 1, so contact can't inject energy. The glance kick
        //    comes from the SLIDE — see `CarTuning.wallFriction` for why press is
        //    useless here — capped at what a square hit would give, so a graze can
        //    never bounce harder than a head-on.
        let squareBounce = press * tuning.wallRestitution * squareness
        let glanceCeiling = abs(slide) * tuning.wallRestitution
        let glanceBounce = min(
            glanceCeiling * tuning.wallGlanceBounce * (1 - squareness) * 0.05,
            press * tuning.wallRestitution)
        let bounced = squareBounce + glanceBounce
        // 2. Friction: a RATE per tick, not an absolute cut, easing off toward a
        //    floor rather than bleeding to a stop. Dragging should be a viable if
        //    slow line (~half speed); the first two attempts left 0% then 2% of
        //    speed after a second, which is flypaper. `headroom` is how far above
        //    the floor the car still is, so the scrub fades as it settles.
        let floor = tuning.maxSpeed * tuning.wallDragFloor
        let headroom = max(0, (abs(slide) - floor) / max(floor, 1))
        let bite = abs(slide) * tuning.wallFriction * Race.dt * min(1, headroom)
        let scrub = min(abs(slide), abs(slide) * min(1, bite))
        let keptSlide = slide - (slide > 0 ? scrub : -scrub)
        car.velocity = normal * bounced + along * keptSlide

        // 3. Yaw toward parallel — a NUDGE, not a grip. Deliberately weak enough
        //    that steering beats it, so a car pinned against a wall can drag-turn
        //    out: `steerRate` is 9 rad/s at full lock and this peaks near a tenth of
        //    that. Direction comes from the slide BEFORE the bounce — after a square
        //    hit the new velocity points away, and aiming at that turned the nose
        //    further off the wall instead of onto it.
        let wallAngle = atan2(along.y, along.x)
        let facing = slide >= 0 ? wallAngle : wallAngle + .pi
        var delta = atan2(sin(facing - car.heading), cos(facing - car.heading))
        let maxTurn = press * tuning.wallYaw * squareness * Race.dt
        delta = max(-maxTurn, min(maxTurn, delta))
        car.heading += delta
    }

    /// Whether the car's path this tick actually passed through the wall segment.
    ///
    /// Proximity alone cannot catch a fast car: the nearest-approach test samples
    /// three points of the movement, so a long enough step has none of them within
    /// reach and the wall is missed entirely — 60 units through the map fence
    /// registered nothing at all. A segment-crossing test does not care how fast
    /// the car was going.
    private func crosses(_ wall: Wall, from: Vec2, to: Vec2) -> Bool {
        func side(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
            (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
        }
        let d1 = side(from, wall.a, wall.b)
        let d2 = side(to, wall.a, wall.b)
        guard (d1 < 0) != (d2 < 0) else { return false }  // same side of the line
        let d3 = side(wall.a, from, to)
        let d4 = side(wall.b, from, to)
        return (d3 < 0) != (d4 < 0)  // and the wall spans the path
    }

    /// A unit normal pointing from the wall toward the side `from` is on — the side
    /// the car came from, and so the side it belongs on.
    private func sideNormal(of wall: Wall, at closest: Vec2, from: Vec2) -> Vec2 {
        let offset = from - closest
        if offset.length > 0.001 { return offset.normalized }
        // Started exactly on the wall: fall back to its own outward face if it has
        // one (rails record it), otherwise let the caller use the end offset.
        return wall.outward.length > 0.001 ? wall.outward : .zero
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
    /// **No tolerance on the top.** A wall's height *is* its top, so a car above it
    /// is over it. A tolerance there gave every wall invisible reach, which made a
    /// ramp's end cap block the legitimate climb: the cap sat at 0.8 but reached
    /// 1.15, and a climber arrives at the mouth at 0.99 (not 1.0 — the per-tick
    /// clamp approaches deck height asymptotically). The floor keeps its tolerance:
    /// that end is about which level the wall belongs to, where a car's size counts.
    func blocks(_ wall: Wall, car: CarState, movedFrom from: Vec2 = .zero) -> Bool {
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
        case .embankment:
            // Earth: solid from the ground up to the road it carries, so a car
            // below cannot drive into a ramp's flank. Above the road there is
            // nothing — a deck crossing over a ramp runs clear.
            guard car.height <= wall.height + Track.reachTolerance else { return false }
            // **ONE-WAY: you may drive OFF a ramp, never INTO it.** Without this a
            // railless ramp would trap you on it, since the earth that stops the
            // car below is the same segment the car above would leave over.
            //
            // The side test is the car's approach against the wall's stored
            // `outward` — which points away from the road this earth carries, so
            // it is a question about the RAMP, not about this segment's geometry.
            // Two cheaper-looking tests are wrong, both tried: "was the car on
            // road" is true of the legitimate driver too, and the NEAREST wall's
            // outward answers "which side of this segment" on a curve.
            return isOutside(wall, from: from)
        case .rail:
            // **A railing guards the level it edges, and does not reach the
            // floor.** It is a waist-high barrier, not a wall to the ground —
            // the earth beneath a raised road is the embankment's job.
            //
            // The floor used to be `trunc(height)`, which split one bridge edge
            // in two: a rail at 0.999 fenced the ground while its neighbour at
            // 1.0 did not, so the fence had holes and a car pushed out by one
            // could be shoved through another. Rounding to the nearest level
            // says what was meant — a rail near deck height IS a deck rail.
            let level = Double(Track.level(of: wall.height))
            let top = max(wall.height, level)
            return car.height >= level - Track.reachTolerance && car.height <= top
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
    /// Whether the car approached from the wall's OUTWARD side — the side its
    /// bulk faces, away from the road it carries.
    ///
    /// A wall with no recorded `outward` has no sides to tell apart, so it stays
    /// symmetric: that is the honest answer for the map boundary and a level
    /// seal, and it is also what older decoded data becomes.
    func isOutside(_ wall: Wall, from: Vec2) -> Bool {
        guard wall.outward.length > 0.001 else { return true }
        return (from - wall.a).dot(wall.outward) > 0
    }

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
