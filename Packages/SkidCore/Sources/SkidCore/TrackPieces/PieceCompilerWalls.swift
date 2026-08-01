import Foundation

/// The walls a piece-built track carries: deck guard rails, ramp embankment
/// sides and caps, and the map boundary fence.
///
/// Split from `PieceCompiler` to keep that file inside the length budget. These
/// are pure geometry — `collideWithWalls` only tests walls on the car's OWN
/// layer, so which layer each wall claims is what decides whether it stops
/// anything.
extension PieceCompiler {
    /// Guard rails down both edges of an elevated piece, as runtime walls.
    ///
    /// Follows the piece's own samples so a curved deck gets a curved rail, and
    /// offsets by the SAME height-scaled half-width the renderer uses
    /// (`Elevation.scale`) — otherwise the barrier a car hits would sit somewhere
    /// other than the edge it can see.
    ///
    /// A ramp is treated as a solid **embankment**: walled all the way round,
    /// with exactly two openings — its low end open at height 0, its high end
    /// open at height 1. That is the only way in or out, so you can't drive onto
    /// a ramp from its flank, and you can't drive *under* it from the ground
    /// while it climbs. (Before this, a ramp's road was reachable from any
    /// direction: its sides were unwalled and its ends open on both layers.)
    static func deckRails(of placed: PlacedPiece, capHighEnd: Bool = true) -> [Wall] {
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
                rails.append(
                    Wall(
                        from: edge[index - 1], to: edge[index], height: height,
                        outward: outward))
            }
        }
        if capHighEnd {
            rails.append(contentsOf: rampEndCaps(left: left, right: right, samples: samples))
        }
        return rails
    }

    /// Whether this elevated piece owns the **high end of a climb**, and so should be
    /// capped underneath.
    ///
    /// The cap belongs to the elevated RUN, not to each piece in it. A ramp climbs,
    /// then flat deck carries on at the same height, then another ramp descends — and
    /// only where the slope meets the deck is there a mouth with open air beneath it.
    ///
    /// Deciding this per piece was wrong the moment a deck could be more than one
    /// piece. With primitives it always is (a 2U deck is two short straights), so
    /// every deck piece claimed its own "high end" and dropped a 0.9 cap straight
    /// across the bridge — walling off the road below at each seam. The old catalog
    /// hid the fault behind a one-piece deck.
    ///
    /// So: **only a climbing placement has a mouth**, and a placement says so —
    /// `climb != 0` (the piece's own delta or its pitch). Deck pieces are
    /// ordinary shapes that happen to sit at height 1; nothing about one marks
    /// it as the end of anything.
    ///
    /// Asking the placement beats inferring from its sampled endpoint heights,
    /// which pick up floating-point drift on level pieces and would answer
    /// "yes" for any future piece that changes height for some other reason.
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
