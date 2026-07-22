import Foundation

/// Built-in tracks, all flat (crossings arrive with the two-layer
/// milestone). Every track: closed asphalt ribbon in grass, directional
/// corridor gates (start/finish last), 4 grid slots, hazards as design.
public enum TrackLibrary {
    /// Every built-in track, in picker order.
    public static var all: [Track] {
        [practiceLoop(), gauntlet(), hairpin(), overpass()]
    }

    /// Lookup by stable id; unknown ids fall back to the practice loop.
    public static func track(id: String) -> Track {
        all.first { $0.id == id } ?? practiceLoop()
    }

    /// Playfield boundary walls, inset from the world edge (shared by all
    /// built-in tracks).
    static func boundaryWalls(size: Vec2) -> [Wall] {
        let inset = 8.0
        let bounds = [
            Vec2(inset, inset), Vec2(size.x - inset, inset),
            Vec2(size.x - inset, size.y - inset), Vec2(inset, size.y - inset),
        ]
        return bounds.indices.map { i in
            Wall(from: bounds[i], to: bounds[(i + 1) % bounds.count])
        }
    }
    // The practice loop's dimensions: a rounded rectangle centered in a
    // 1600×1000 world, with the top straight pinched toward the middle to
    // make one interesting drift corner.
    private static let worldSize = Vec2(1600, 1000)
    private static let ribbonWidth = 130.0
    private static let cx = 800.0
    private static let cy = 500.0
    private static let halfX = 560.0  // straight half-length, x
    private static let halfY = 300.0  // straight half-length, y
    private static let corner = 170.0  // corner radius
    private static var bottom: Double { cy + halfY }
    private static var top: Double { cy - halfY }
    private static var right: Double { cx + halfX }
    private static var left: Double { cx - halfX }

    /// A rounded-rectangle circuit with a pinched waist on the top straight.
    /// Asphalt ribbon in grass, boundary walls at the playfield edge, four
    /// checkpoint gates (the last is start/finish on the bottom straight,
    /// driven left-to-right).
    public static func practiceLoop() -> Track {
        Track(
            id: "practice-loop",
            centerline: centerline(),
            width: ribbonWidth,
            walls: boundaryWalls(size: worldSize),
            gates: gates(),
            patches: patches(),
            startSlots: startSlots(),
            startHeading: 0,
            size: worldSize
        )
    }

    private static func centerline() -> [Vec2] {
        var points: [Vec2] = []
        // Start at the left end of the bottom straight, wind clockwise on
        // screen (y grows downward): bottom straight → right corners → top
        // (with pinch) → left corners → back.
        func arc(center: Vec2, from: Double, to: Double, steps: Int) {
            for i in 0...steps {
                let angle = from + (to - from) * Double(i) / Double(steps)
                points.append(center + Vec2(angle: angle) * corner)
            }
        }
        // Bottom straight, left → right.
        points.append(Vec2(left + corner, bottom))
        points.append(Vec2(right - corner, bottom))
        // Bottom-right corner (90° → 0°).
        arc(center: Vec2(right - corner, bottom - corner), from: .pi / 2, to: 0, steps: 6)
        // Right side, up.
        points.append(Vec2(right, top + corner))
        // Top-right corner (0° → -90°).
        arc(center: Vec2(right - corner, top + corner), from: 0, to: -.pi / 2, steps: 6)
        // Top straight with a pinch: dip toward the middle and back out.
        points.append(Vec2(cx + 190, top))
        points.append(Vec2(cx + 60, top + 130))
        points.append(Vec2(cx - 60, top + 130))
        points.append(Vec2(cx - 190, top))
        // Top-left corner (-90° → -180°).
        arc(center: Vec2(left + corner, top + corner), from: -.pi / 2, to: -.pi, steps: 6)
        // Left side, down.
        points.append(Vec2(left, bottom - corner))
        // Bottom-left corner (180° → 90°).
        arc(center: Vec2(left + corner, bottom - corner), from: .pi, to: .pi / 2, steps: 6)
        return points
    }

    /// Gates at the four compass midpoints, ordered along the driving
    /// direction (each directional); start/finish last, on the bottom
    /// straight. Gates are FORGIVING: each spans the whole corridor — from a
    /// modest reach into the infield out to the boundary wall — so running
    /// wide over grass still counts (grass already taxes speed). Only a
    /// gross cut across the middle misses one.
    private static func gates() -> [Gate] {
        let wall = 8.0
        // How far past the inner ribbon edge a gate reaches into the
        // infield. Deep enough that a rally line through the grass counts,
        // shallow enough that circling the infield center can't lap.
        let infieldReach = ribbonWidth / 2 + 150
        return [
            // Right side, driving up: infield → right wall.
            Gate(
                from: Vec2(right - infieldReach, cy), to: Vec2(worldSize.x - wall, cy),
                forward: Vec2(0, -1)),
            // Pinch on the top straight, driving left: top wall → infield.
            Gate(
                from: Vec2(cx, wall), to: Vec2(cx, top + 130 + infieldReach),
                forward: Vec2(-1, 0)),
            // Left side, driving down: left wall → infield.
            Gate(
                from: Vec2(wall, cy), to: Vec2(left + infieldReach, cy),
                forward: Vec2(0, 1)),
            // Start/finish on the bottom straight, driving right:
            // infield → bottom wall.
            Gate(
                from: Vec2(cx, bottom - infieldReach), to: Vec2(cx, worldSize.y - wall),
                forward: Vec2(1, 0)),
        ]
    }

    /// The hazards, placed as track design: an oil slick on the right
    /// straight before the corner, mud pinching the bottom straight's entry,
    /// and water clipping the exit of the top-right corner.
    private static func patches() -> [SurfacePatch] {
        [
            SurfacePatch(center: Vec2(right - 20, cy + 90), radius: 34, surface: .oil),
            SurfacePatch(center: Vec2(left + 260, bottom - 52), radius: 55, surface: .mud),
            SurfacePatch(center: Vec2(cx + 320, top + 44), radius: 48, surface: .water),
        ]
    }

    /// Grid on the bottom straight, before the start line, facing +x.
    private static func startSlots() -> [Vec2] {
        (0..<4).map { i in
            Vec2(cx - 70 - Double(i) * 50, bottom + (i % 2 == 0 ? -28 : 28))
        }
    }
}
