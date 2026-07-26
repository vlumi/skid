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
        for edge in [left, right] {
            for index in 1..<edge.count {
                let height = (samples[index - 1].height + samples[index].height) / 2
                rails.append(Wall(from: edge[index - 1], to: edge[index], height: height))
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
    /// So: only a piece that actually rises or falls has a mouth to seal. Flat deck
    /// is high along its whole length — there is no "high end" of it, and the air
    /// beneath it is already sealed by the ramps at either end of the run.
    static func capsHighEnd(_ piece: PlacedPiece) -> Bool {
        abs(piece.exitHeight - piece.entryHeight) > Track.heightEpsilon
    }

    /// The end caps that make a ramp a closed embankment you cannot drive under.
    ///
    /// **The high end is the important one.** A ramp rises off the ground, so the
    /// space beneath its upper reaches is open air — driving in there is driving
    /// *through* the embankment. Sealing it needs a wall across the ramp's mouth at
    /// a height just BELOW the deck: high enough to stop everything underneath,
    /// low enough that a car arriving along the ramp at deck height passes over it
    /// and onto the bridge.
    ///
    /// That height also has to be picked with the wall rule in mind
    /// (`Race.blocks`): a wall blocks from `trunc(height)` up to `height`, so a cap
    /// at 0.99 blocks 0…0.99 — everything under the deck — while the deck itself
    /// (1.0) is clear. A cap at exactly 1.0 would have floor 1 and stop nothing
    /// below, which is why it can't simply sit at deck height.
    ///
    /// The caps span the full width between the side rails' endpoints, so they meet
    /// the sides exactly and leave no gap at the corners.
    ///
    /// The low end gets NO cap. It's the way in, and a wall there would have to
    /// claim deck height to let ground cars through — which puts a "height 1" wall
    /// 192 units from any deck-height road, misrepresenting where the deck is (a
    /// test flagged exactly that). A car on the deck can't reach the ramp's foot
    /// anyway: it would have to descend the slope to get there, which means it is
    /// no longer at deck height.
    private static func rampEndCaps(
        left: [Vec2], right: [Vec2], samples: [(point: Vec2, height: Double)]
    ) -> [Wall] {
        guard let leftFirst = left.first, let leftLast = left.last,
            let rightFirst = right.first, let rightLast = right.last,
            let firstHeight = samples.first?.height, let lastHeight = samples.last?.height
        else { return [] }
        // The high end: a climb ends high, a descent starts high.
        let high = lastHeight > firstHeight ? (leftLast, rightLast) : (leftFirst, rightFirst)
        // Under the raised end: solid to everyone below the deck.
        return [Wall(from: high.0, to: high.1, height: underDeckCapHeight)]
    }

    /// The cap height under a ramp's raised end.
    ///
    /// It has to clear the highest a car climbing the ramp actually reaches, and
    /// that is NOT 1.0: the per-tick height clamp means the car approaches deck
    /// height asymptotically, so it arrives at the mouth around 0.99. A cap at
    /// 0.99 therefore blocked the legitimate climb — the car hit its own exit
    /// (measured: heights near the cap ran 0.939…0.993).
    ///
    /// So it sits at 0.9: high enough that the only way past is to be nearly at
    /// deck height (which means having climbed the ramp), low enough to clear the
    /// arriving climber. With floor = trunc(0.9) = 0 it blocks 0…0.9 — everything
    /// meaningfully below the deck.
    private static let underDeckCapHeight = 0.9

    /// The map fence: a rectangle just inside the track's own bounds, on both
    /// layers, so a car can't drive off into the surrounding void.
    ///
    /// Piece-built tracks had none of this — you could drive out of the map
    /// entirely and off under the control band. Legacy `TrackDesign` tracks
    /// always had it (`boundaryWalls`), which is why this only showed up on
    /// editor tracks.
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
