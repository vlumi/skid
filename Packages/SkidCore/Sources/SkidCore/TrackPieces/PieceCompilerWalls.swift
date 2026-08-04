import Foundation

/// The walls a piece-built track carries: deck guard rails, ramp embankment
/// sides and caps, and the map boundary fence.
///
/// Split from `PieceCompiler` to keep that file inside the length budget. Pure
/// geometry: each wall carries the height it guards, and `Race.blocks` decides
/// from that whether it stops a given car.
extension PieceCompiler {
    /// Guard rails down both edges of an elevated piece, as runtime walls.
    ///
    /// Follows the piece's own samples, so a curved deck gets a curved rail.
    ///
    /// A climbing piece gets an embankment beneath it — the earth a ramp stands
    /// on, so you cannot drive into its flank or under it while it climbs — and, if
    /// the author asked for one, a railing on each edge guarding the road it
    /// carries.
    ///
    /// `railed` is the author's per-piece toggle (see `TrackLayout.railed`). The
    /// embankment and the mouth seal ignore it: they are structure, not decoration,
    /// and a railless ramp still may not be entered from below or driven into from
    /// the side.
    ///
    /// They were one wall until device testing showed why they cannot be. A
    /// railing stretched to the floor made a bridge edge solid in some places
    /// and see-through in others; lifting it to its own level removed the ramp's
    /// side barrier. Two jobs, two walls.
    static func deckRails(
        of placed: PlacedPiece, capHighEnd: Bool = true, railed: Bool = true
    ) -> [Wall] {
        let samples = placed.heightedSamples(degreesPerSample: degreesPerSample)
        guard samples.count >= 2 else { return [] }
        let entryDir = Vec2(angle: placed.entry.heading.radians)
        let exitDir = Vec2(angle: placed.exits[0].heading.radians)
        var left: [Vec2] = []
        var right: [Vec2] = []
        for index in samples.indices {
            let direction: Vec2
            if index == 0 {
                direction = entryDir
            } else if index == samples.count - 1 {
                direction = exitDir
            } else {
                direction = (samples[index + 1].point - samples[index - 1].point).normalized
            }
            // The TRUE road edge, not the height-scaled visual one. The road a
            // car can drive on is `width` wide at every height (grip width never
            // scales — only the drawing does), so scaling the rail by
            // `Elevation.scale` pushed it steadily outboard as the ramp climbed:
            // measured 0.2 units from the edge at the ramp's foot but 8+ by
            // mid-ramp, which is the reported "walls don't reach the bottom of
            // the ramp" and part of the gap cars slipped through.
            let side = direction.perpendicular * (Double(PieceCatalog.width) / 2)
            left.append(samples[index].point + side)
            right.append(samples[index].point - side)
        }
        // Each rail sits at the HEIGHT of the road it guards, so it bites a car
        // at that height and lets anything at a very different height pass. On a
        // ramp this falls out for free: the rail at each sample takes that
        // sample's own height, so the barrier climbs with the slope and a car
        // passing underneath at height 0 never touches it.
        var rails: [Wall] = []
        // The offset that built each edge IS its outward direction, so record it
        // rather than leave the physics to guess (it cannot — see `Wall.outward`).
        for (edge, sign) in [(left, 1.0), (right, -1.0)] {
            for index in 1..<edge.count {
                let height = (samples[index - 1].height + samples[index].height) / 2
                let along = edge[index] - edge[index - 1]
                let outward =
                    along.length > 0
                    ? along.perpendicular.normalized * sign : Vec2.zero
                // **The railing is the author's choice; the earth is not.** A
                // railless bridge is a legitimate track — you may drive off the
                // edge and fall — but the ground beneath a climb is structural
                // either way, or a car could drive into the flank of thin air.
                if railed {
                    rails.append(
                        Wall(
                            from: edge[index - 1], to: edge[index], height: height,
                            outward: outward, onClimb: placed.climb != 0))
                }
                // A climbing stretch also stands on earth. Same line, same
                // height — what differs is what it blocks: the railing guards
                // the road's own level, this fills everything below it.
                if placed.climb != 0 {
                    rails.append(
                        Wall(
                            from: edge[index - 1], to: edge[index], height: height,
                            kind: .embankment, outward: outward))
                }
            }
        }
        // The mouth seal is structural too: it is what stops a car entering a
        // raised road from the level below, which has nothing to do with whether
        // the author wanted a railing.
        if capHighEnd {
            rails.append(contentsOf: rampEndCaps(left: left, right: right, samples: samples))
        }
        return rails
    }

    /// Whether this piece owns the **high end of a climb**, and so needs capping
    /// underneath. Only a climbing placement has a mouth with open air beneath it;
    /// a deck piece is an ordinary shape that happens to sit at height 1.
    ///
    /// Deciding it per piece by endpoint height was wrong the moment a deck could
    /// be more than one piece — with primitives it always is (a 2U deck is two
    /// short straights), so every deck piece claimed its own high end and dropped
    /// a cap across the bridge, walling off the road below at each seam. Asking
    /// the placement also avoids the float drift a sampled height picks up.
    static func capsHighEnd(_ piece: PlacedPiece) -> Bool {
        piece.climb != 0
    }

    /// The seal under a ramp's raised end, as a **gate**: a one-way level wall
    /// that blocks entering from a road below this level, and nothing else.
    ///
    /// A ramp rises off the ground, so the space beneath its upper reaches is
    /// open air — driving in there is driving *through* the embankment. The seal
    /// used to be an ordinary rail at a tuned height (0.9): tall enough that only
    /// a car nearly at deck height cleared its top, short enough that the
    /// arriving climber did clear it — a coupling to the climb physics that had
    /// already broken once (a 0.99 cap blocked the legitimate climb, because the
    /// per-tick height clamp lands the climber at ~0.99, not 1.0). A gate says
    /// what was always meant: you must effectively BE of the upper level to pass.
    ///
    /// The threshold is `level − reachTolerance` — the same "within a car's own
    /// reach of a level" tolerance the rail floor rule uses — so there is no
    /// bespoke constant left to tune. It still must sit below the worst-case
    /// arrival height of a flat-out climber; `RampGateTests` pins that for every
    /// ramp in the catalog, so a steeper future ramp or a slower climb clamp
    /// fails a test instead of a player.
    ///
    /// The gate spans the full width between the side rails' endpoints, so it
    /// meets the sides exactly and leaves no gap at the corners.
    ///
    /// The low end gets NO seal. It's the way in, and a car of the upper level
    /// can't reach the foot anyway: it would have to descend the slope to get
    /// there, which means it is no longer at that level.
    private static func rampEndCaps(
        left: [Vec2], right: [Vec2], samples: [(point: Vec2, height: Double)]
    ) -> [Wall] {
        guard let leftFirst = left.first, let leftLast = left.last,
            let rightFirst = right.first, let rightLast = right.last,
            let firstHeight = samples.first?.height, let lastHeight = samples.last?.height
        else { return [] }
        // The high end: a climb ends high, a descent starts high. The gate's
        // threshold comes from the MOUTH'S OWN height, not a rounded storey —
        // a half-climb's mouth at 0.5 gets a gate at 0.3, admitting the
        // arriving half-climber and stopping the ground; rounding to a storey
        // put an unreachable 0.8 gate on it.
        let high = lastHeight > firstHeight ? (leftLast, rightLast) : (leftFirst, rightFirst)
        return [
            Wall(
                from: high.0, to: high.1,
                height: max(firstHeight, lastHeight) - Track.reachTolerance,
                kind: .gate)
        ]
    }

    /// The map fence: a rectangle just inside the track's own bounds, so a car
    /// can't drive off into the surrounding void.
    static func boundaryWalls(size: Vec2) -> [Wall] {
        let inset = 8.0
        let corners = [
            Vec2(inset, inset), Vec2(size.x - inset, inset),
            Vec2(size.x - inset, size.y - inset), Vec2(inset, size.y - inset),
        ]
        // A boundary wall stops a car at ANY height (see `Wall.Kind.boundary`),
        // so one ring is enough — falling off the world is no better up on the
        // deck.
        return [0].flatMap { _ in
            corners.indices.map { index in
                Wall(
                    from: corners[index], to: corners[(index + 1) % corners.count],
                    kind: .boundary)
            }
        }
    }
}
