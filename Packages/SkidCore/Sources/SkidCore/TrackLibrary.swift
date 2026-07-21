import Foundation

/// Built-in tracks. v0.1 ships exactly one: a flat practice loop for
/// answering "is the drift fun?".
public enum TrackLibrary {
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
            centerline: centerline(),
            width: ribbonWidth,
            walls: boundaryWalls(),
            gates: gates(),
            patches: [],
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

    /// Playfield boundary walls, inset from the world edge.
    private static func boundaryWalls() -> [Wall] {
        let inset = 8.0
        let bounds = [
            Vec2(inset, inset), Vec2(worldSize.x - inset, inset),
            Vec2(worldSize.x - inset, worldSize.y - inset), Vec2(inset, worldSize.y - inset),
        ]
        return bounds.indices.map { i in
            Wall(from: bounds[i], to: bounds[(i + 1) % bounds.count])
        }
    }

    /// Gates across the ribbon at the four compass midpoints, ordered along
    /// the driving direction; start/finish last, on the bottom straight.
    private static func gates() -> [Gate] {
        func gate(at center: Vec2, across direction: Vec2) -> Gate {
            let half = direction.normalized * (ribbonWidth / 2 + 20)
            return Gate(from: center - half, to: center + half)
        }
        return [
            gate(at: Vec2(right, cy), across: Vec2(1, 0)),  // right side, heading up
            gate(at: Vec2(cx, top + 130), across: Vec2(0, 1)),  // mid-pinch, heading left
            gate(at: Vec2(left, cy), across: Vec2(1, 0)),  // left side, heading down
            gate(at: Vec2(cx, bottom), across: Vec2(0, 1)),  // start/finish
        ]
    }

    /// Grid on the bottom straight, before the start line, facing +x.
    private static func startSlots() -> [Vec2] {
        (0..<4).map { i in
            Vec2(cx - 70 - Double(i) * 50, bottom + (i % 2 == 0 ? -28 : 28))
        }
    }
}
