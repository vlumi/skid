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
    static func deckRails(of placed: PlacedPiece) -> [Wall] {
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
            let half =
                Double(PieceCatalog.width) / 2 * Elevation.scale(atHeight: samples[index].height)
            let side = direction.perpendicular * half
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
        return rails
    }

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
