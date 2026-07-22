import Foundation

extension TrackLibrary {
    /// "Gauntlet": the rounded rectangle pinched on BOTH straights, on a
    /// narrower ribbon — two flowing chicanes per lap and hazards guarding
    /// each. Start/finish sits on the right half of the bottom straight,
    /// clear of the bottom pinch.
    static let gauntletDesign = TrackDesign(
        id: "gauntlet",
        name: "Gauntlet",
        size: Vec2(1600, 1000),
        width: 112,
        nodes: [
            .init(id: 1, position: Vec2(240, 800), fillet: 170),
            // The bottom pinch, on the straight's left half.
            .init(id: 2, position: Vec2(470, 800), fillet: 45),
            .init(id: 3, position: Vec2(540, 672), fillet: 40),
            .init(id: 4, position: Vec2(620, 672), fillet: 40),
            .init(id: 5, position: Vec2(690, 800), fillet: 45),
            .init(id: 6, position: Vec2(1360, 800), fillet: 170),
            .init(id: 7, position: Vec2(1360, 200), fillet: 170),
            // The top pinch, mirroring the practice loop's.
            .init(id: 8, position: Vec2(990, 200), fillet: 55),
            .init(id: 9, position: Vec2(860, 330), fillet: 45),
            .init(id: 10, position: Vec2(740, 330), fillet: 45),
            .init(id: 11, position: Vec2(610, 200), fillet: 55),
            .init(id: 12, position: Vec2(240, 200), fillet: 170),
        ],
        gates: [
            .init(node: 6, t: 0.5),  // right side, driving up
            .init(node: 9, t: 0.5),  // top pinch, driving left
            .init(node: 12, t: 0.5),  // left side, driving down
            .init(node: 5, t: 310.0 / 670.0),  // start/finish at x = 1000
        ],
        hazards: [
            // The pinches bite: oil on the top pinch exit, mud filling the
            // bottom pinch apex, water on the right straight.
            SurfacePatch(center: Vec2(590, 230), radius: 32, surface: .oil),
            SurfacePatch(center: Vec2(580, 740), radius: 48, surface: .mud),
            SurfacePatch(center: Vec2(1336, 370), radius: 44, surface: .water),
        ],
        pit: Vec2(800, 550)
    )
}
