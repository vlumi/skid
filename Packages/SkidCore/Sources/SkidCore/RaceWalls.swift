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
        for wall in walls ?? track.walls where blocks(wall, car: car) {
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
            let side = approach.length > 0 ? approach : offset.normalized
            guard side.length > 0 else { continue }
            // **The push-out uses the approach side; the physics uses the wall's own
            // FACE.** They are different vectors and conflating them was wrong: the
            // approach direction points from the wall to wherever the car came from,
            // which on a long wall is diagonal, so a graze got resolved against a
            // slanted "normal" and came back off harder than it went in. The face is
            // perpendicular to the wall, signed to the side the car is on.
            let normal = faceNormal(of: wall, towards: side)
            // **Push out along the FACE only — do not teleport onto the wall.**
            //
            // `closest + side * reach` is an absolute position on the wall's surface,
            // recomputed every tick. `closest` tracks the car's PATH, so a car held
            // against a rail was snapped to the same spot each tick and lost ALL its
            // motion, not just the into-wall part. On device that read as the car
            // being glued in place while the debug overlay showed it doing 300+ —
            // velocity was never the problem, position was, which is why no wall
            // tuning could touch it.
            //
            // Now only the overlap is removed: the car keeps every bit of travel
            // along the wall and is nudged out just far enough to be clear.
            let overlap = reach - (car.position - closest).dot(normal)
            if overlap > 0 { car.position += normal * overlap }
            let intoWall = car.velocity.dot(normal)
            guard intoWall < 0 else { continue }
            respond(car: &car, normal: normal, intoWall: intoWall)
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

    /// Below this the hit is a pure glance — no bounce at all, just scrape. An
    /// arcade car clipping a barrier at 30° should slide along it, not come off.
    static let glancingAngle = 30.0
    /// At or above this it is a pure head-on, with the full bounce.
    static let headOnAngle = 75.0

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

        // 1. Bounce: the into-wall component comes back, scaled from a subdued
        //    glance bounce up to full restitution head-on. A pure glance keeps SOME
        //    kick — zero read as flypaper on device — and the scale is never above 1,
        //    so contact can't inject energy.
        // **A glance bounce must not be proportional to `press`.** While dragging,
        // `press` is about 1 unit/s — so `press * restitution * scale` came out under
        // half a unit however high the slider went, and the glance bounce did nothing
        // at all (device: "no glance bounce no matter what value I put in"). The kick
        // a graze gives comes from the speed the car is carrying ALONG the wall, which
        // is the energy actually available.
        // A glance's kick comes from the slide, but must never EXCEED what a square
        // hit at the same speed would give — otherwise a shallow graze bounces harder
        // than a head-on one, which is backwards. Capped at the press-based bounce a
        // fully square hit would produce.
        let squareBounce = press * tuning.wallRestitution * squareness
        let glanceCeiling = abs(slide) * tuning.wallRestitution
        let glanceBounce = min(
            glanceCeiling * tuning.wallGlanceBounce * (1 - squareness) * 0.05,
            press * tuning.wallRestitution)
        let bounced = squareBounce + glanceBounce
        // 2. Friction: a RATE per tick, not an absolute cut, and it EASES OFF toward
        //    a floor rather than bleeding to a stop. Dragging a wall should be a
        //    viable if slow line — device feel says around half speed is fine for
        //    balance — where the first two attempts left 0% and then 2% of speed
        //    after a second of dragging, which is flypaper, not a scrape.
        //
        //    `headroom` is how far above the floor the car still is, so the scrub
        //    fades as it settles: fast means real cost, at the floor means none.
        // Friction also keys off the SLIDE, not the press. Pressed lightly against a
        // barrier the car is still scraping along it at speed, and that is what a
        // scrape costs — keying off `press` meant dragging was nearly free (device:
        // "the car could slow down some more when dragging").
        let floor = tuning.maxSpeed * tuning.wallDragFloor
        let headroom = max(0, (abs(slide) - floor) / max(floor, 1))
        let bite = abs(slide) * tuning.wallFriction * Race.dt * min(1, headroom)
        let scrub = min(abs(slide), abs(slide) * min(1, bite))
        let keptSlide = slide - (slide > 0 ? scrub : -scrub)
        car.velocity = normal * bounced + along * keptSlide

        // 3. Yaw toward parallel — a NUDGE, not a grip. Whichever way round the wall
        //    runs, turn the nose the short way onto it, scaled by both the press and
        //    the squareness so a light graze barely moves it and a heavy one swings
        //    the car straight.
        //
        //    Deliberately weak enough that steering beats it: pinned against a wall
        //    and wanting out, DRAG-TURNING has to work (backing up and three-point
        //    turning is tedious), so this must not hold the nose parallel against the
        //    driver's input. `steerRate` is 9 rad/s at full lock; this peaks around a
        //    tenth of that.
        //
        //    Which way along the wall the car is GOING comes from the slide BEFORE
        //    the bounce: after a square hit the new velocity points away from the
        //    wall, and aiming at that turned the nose further off instead of onto it.
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
