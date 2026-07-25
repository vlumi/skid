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
        // Which layers these rails block. `collideWithWalls` only tests walls on
        // the car's OWN layer, so this decides what the barrier actually stops.
        //
        // A flat deck piece guards layer 1 — only a car up there can fall off it.
        // A ramp's SIDES guard both layers, since a climbing car is still layer 0
        // while a descending one is already layer 1, and neither may leave
        // sideways.
        let sloped = placed.piece.heightDelta != 0 || placed.piece.launches
        let layers = sloped ? [0, 1] : [Int(max(placed.entryHeight, placed.exitHeight).rounded())]
        var rails: [Wall] = []
        for layer in layers {
            for edge in [left, right] {
                for index in 1..<edge.count {
                    rails.append(Wall(from: edge[index - 1], to: edge[index], layer: layer))
                }
            }
        }
        if sloped {
            rails.append(contentsOf: rampEndCaps(placed, left: left, right: right))
        }
        return rails
    }

    /// The **low** end of a ramp embankment, sealed against anyone up on the
    /// deck: a car at height 1 can't drop off the bottom of the slope.
    ///
    /// Only the low end gets a cap. The high end can't have one, and this is
    /// worth being precise about: the layer-switch line sits exactly there (the
    /// whole point of the earlier fix), so a climbing car is still layer 0 when it
    /// arrives and a layer-0 wall at that spot would block it from its own exit —
    /// measured as sitting 0 away from the ramp line, well inside a car radius.
    /// A ground car approaching the ramp's raised end head-on is instead stopped
    /// by the side rails converging there, and by the map boundary beyond.
    private static func rampEndCaps(_ placed: PlacedPiece, left: [Vec2], right: [Vec2]) -> [Wall] {
        guard let leftFirst = left.first, let leftLast = left.last,
            let rightFirst = right.first, let rightLast = right.last
        else { return [] }
        // Which end is low? A climb starts low; a descent ends low.
        let climbing = placed.piece.heightDelta > 0
        let low = climbing ? (leftFirst, rightFirst) : (leftLast, rightLast)
        return [Wall(from: low.0, to: low.1, layer: 1)]
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
        // Both layers: falling off the world is no better up on the deck.
        return [0, 1].flatMap { layer in
            corners.indices.map { index in
                Wall(
                    from: corners[index], to: corners[(index + 1) % corners.count],
                    layer: layer)
            }
        }
    }
}
