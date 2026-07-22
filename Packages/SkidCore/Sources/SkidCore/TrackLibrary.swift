import Foundation

/// Built-in tracks, authored as `TrackDesign` values and compiled once at
/// first use. Every track: closed asphalt ribbon in grass, directional
/// corridor gates (start/finish last), 4 grid slots, hazards as design.
public enum TrackLibrary {
    /// Every built-in design, in picker order.
    static let designs: [TrackDesign] = [
        practiceLoopDesign, gauntletDesign, hairpinDesign, overpassDesign,
    ]

    /// Every built-in track, compiled once — the designs are build
    /// artifacts, so a failure here is a broken build, not a runtime
    /// condition to limp through.
    public static let all: [Track] = designs.map { design in
        do {
            return try design.compile()
        } catch {
            fatalError("built-in design '\(design.id)' failed to compile: \(error)")
        }
    }

    /// Lookup by stable id; unknown ids fall back to the practice loop.
    public static func track(id: String) -> Track {
        all.first { $0.id == id } ?? all[0]
    }

    /// The authored display name for a track id.
    public static func displayName(id: String) -> String {
        designs.first { $0.id == id }?.name ?? id
    }

    // Named accessors for the built-ins (tests and demos use these).
    public static func practiceLoop() -> Track { track(id: "practice-loop") }
    public static func gauntlet() -> Track { track(id: "gauntlet") }
    public static func hairpin() -> Track { track(id: "hairpin") }
    public static func overpass() -> Track { track(id: "overpass") }

    /// A rounded-rectangle circuit with a pinched waist on the top
    /// straight to make one interesting drift corner. The pinch corners
    /// carry small fillets, so the chicane flows instead of kinking.
    static let practiceLoopDesign = TrackDesign(
        id: "practice-loop",
        name: "Practice",
        size: Vec2(1600, 1000),
        width: 130,
        nodes: [
            .init(id: 1, position: Vec2(240, 800), fillet: 170),
            .init(id: 2, position: Vec2(1360, 800), fillet: 170),
            .init(id: 3, position: Vec2(1360, 200), fillet: 170),
            .init(id: 4, position: Vec2(990, 200), fillet: 55),
            .init(id: 5, position: Vec2(860, 330), fillet: 45),
            .init(id: 6, position: Vec2(740, 330), fillet: 45),
            .init(id: 7, position: Vec2(610, 200), fillet: 55),
            .init(id: 8, position: Vec2(240, 200), fillet: 170),
        ],
        gates: [
            .init(node: 2, t: 0.5),  // right side, driving up
            .init(node: 5, t: 0.5),  // the pinch, driving left
            .init(node: 8, t: 0.5),  // left side, driving down
            .init(node: 1, t: 0.5),  // start/finish, driving right
        ],
        hazards: [
            // Oil on the right straight before the corner, mud pinching
            // the bottom straight's entry, water clipping the top-right
            // corner's exit.
            SurfacePatch(center: Vec2(1340, 590), radius: 34, surface: .oil),
            SurfacePatch(center: Vec2(500, 748), radius: 55, surface: .mud),
            SurfacePatch(center: Vec2(1120, 244), radius: 48, surface: .water),
        ],
        pit: Vec2(800, 550)
    )
}
