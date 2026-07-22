import Foundation

extension TrackLibrary {
    /// "Overpass": the figure-eight — two lobes crossing in the middle,
    /// one diagonal carried over the other on a bridge. The dive is
    /// rampUp → deck → rampDown edges; the compiler derives the layer
    /// transitions at the deck boundaries and the retaining walls along
    /// the slopes. The joins where the diagonals meet the lobes carry
    /// fillets, so the eight flows instead of kinking.
    static let overpassDesign = TrackDesign(
        id: "overpass",
        name: "Overpass",
        size: Vec2(1600, 1000),
        width: 110,
        nodes: [
            // Diagonal → bottom-right straight (the under-bridge road's
            // exit onto the start straight).
            .init(id: 1, position: Vec2(873, 810), fillet: 45),
            .init(id: 2, position: Vec2(1320, 810), fillet: 170),
            .init(id: 3, position: Vec2(1320, 190), fillet: 170),
            // The dive: sloped approach, elevated deck, sloped descent.
            // Deck boundaries stay sharp — they carry the layer flip.
            .init(id: 4, position: Vec2(950, 190), fillet: 40, edge: .rampUp),
            .init(id: 5, position: Vec2(905, 293), edge: .deck),
            .init(id: 6, position: Vec2(745, 657), edge: .rampDown),
            .init(id: 7, position: Vec2(700, 760), fillet: 30),
            .init(id: 8, position: Vec2(650, 810), fillet: 35),
            .init(id: 9, position: Vec2(280, 810), fillet: 170),
            .init(id: 10, position: Vec2(280, 190), fillet: 170),
            // Top → the flat diagonal back down under the bridge, closing
            // the eight (edge 11 → 1).
            .init(id: 11, position: Vec2(650, 190), fillet: 45),
        ],
        gates: [
            .init(node: 2, t: 0.5, span: .corridor(reach: 130)),  // right lobe, up
            // Mid-bridge, elevated — the crossing that must be earned.
            .init(node: 5, t: 0.5, span: .deck),
            .init(node: 9, t: 0.5, span: .corridor(reach: 130)),  // left lobe, up
            // Mid flat diagonal, under the bridge (y = 483).
            .init(node: 11, t: 293.0 / 620.0, span: .absolute(half: 90)),
            // Start/finish on the bottom-right straight (x = 1090).
            .init(node: 1, t: 217.0 / 447.0, span: .corridor(reach: 110)),
        ],
        hazards: [
            SurfacePatch(center: Vec2(1320, 700), radius: 40, surface: .water),
            SurfacePatch(center: Vec2(365, 275), radius: 42, surface: .mud),
            SurfacePatch(center: Vec2(560, 815), radius: 30, surface: .oil),
        ],
        grid: TrackDesign.StartGrid(back: 50, gap: 45, lateral: 26),
        pit: Vec2(1040, 550),
        extraWalls: [
            // Retaining rails down the bridge deck's middle (layer 1 ONLY —
            // the road running underneath passes clean through), so
            // reaching the mid-bridge gate isn't a tightrope. They cover
            // the span's middle three-fifths, leaving the ramp mouths
            // open. Authored here until the compiler learns a rails flag.
            Wall(from: Vec2(822.6, 343.7), to: Vec2(726.6, 562.1), layer: 1),
            Wall(from: Vec2(923.4, 387.9), to: Vec2(827.4, 606.3), layer: 1),
        ]
    )
}
