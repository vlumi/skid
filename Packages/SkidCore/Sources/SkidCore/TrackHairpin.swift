import Foundation

extension TrackLibrary {
    /// "Hairpin": a fast right-side bowl feeding a peninsula on the left —
    /// a tight 180° hairpin with narrow grass slivers between its lanes.
    /// The tip is TWO 80-radius nodes (a single node can't fillet a ~180°
    /// turn), which bake into one smooth compound arc around x ≈ 980.
    static let hairpinDesign = TrackDesign(
        id: "hairpin",
        name: "Hairpin",
        size: Vec2(1600, 1000),
        width: 116,
        nodes: [
            .init(id: 1, position: Vec2(1350, 820), fillet: 170),
            .init(id: 2, position: Vec2(1350, 190), fillet: 170),
            .init(id: 3, position: Vec2(470, 190), fillet: 170),
            // Dive right into the peninsula…
            .init(id: 4, position: Vec2(470, 480), fillet: 60),
            // …around the tip…
            .init(id: 5, position: Vec2(980, 525), fillet: 80),
            .init(id: 6, position: Vec2(980, 680), fillet: 80),
            // …and back out along the return lane.
            .init(id: 7, position: Vec2(620, 680), fillet: 40),
            .init(id: 8, position: Vec2(430, 700), fillet: 40),
            .init(id: 9, position: Vec2(355, 760), fillet: 25),
            .init(id: 10, position: Vec2(350, 820), fillet: 30),
        ],
        gates: [
            .init(node: 1, t: 320.0 / 630.0),  // right side, driving up
            .init(node: 2, t: 450.0 / 880.0),  // top straight, driving left
            // The hairpin apex, ON the tip's cross edge: a short line only
            // reachable by actually rounding the far end — cutting the
            // neck straight to the return lane crosses y ≈ 600 well left
            // of it and never trips the gate, so the loop must be driven.
            .init(node: 5, t: 74.5 / 155.0, span: .absolute(half: 80)),
            // Start/finish. The reach is deliberately SHALLOW: the return
            // lane runs directly above this stretch, and a standard-reach
            // gate would poke into it — crossable early by a lap-stealing
            // wiggle. 17 keeps the gate just under the return lane's edge.
            .init(node: 10, t: 0.41, span: .corridor(reach: 17)),
        ],
        hazards: [
            // Mud guards the hairpin entry, oil the flat-out top straight,
            // water the corner onto the right side.
            SurfacePatch(center: Vec2(700, 578), radius: 42, surface: .mud),
            SurfacePatch(center: Vec2(820, 190), radius: 30, surface: .oil),
            SurfacePatch(center: Vec2(1350, 660), radius: 42, surface: .water),
        ],
        pit: Vec2(760, 360)
    )
}
