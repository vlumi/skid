import Foundation

extension TrackLibrary {
    /// "Hairpin": a fast right-side bowl feeding a peninsula on the left —
    /// a tight 180° hairpin with narrow grass slivers between its lanes.
    /// Drift heaven; the apex carries its own checkpoint so the corner
    /// must actually be driven (a shallow cut across the tip still counts).
    public static func hairpin() -> Track {
        let size = Vec2(1600, 1000)
        let width = 116.0
        let points = hairpinCenterline()
        let wall = 8.0
        let reach = width / 2 + 150
        let gates = [
            Gate(
                from: Vec2(1350 - reach, 500), to: Vec2(size.x - wall, 500),
                forward: Vec2(0, -1)),
            Gate(from: Vec2(900, wall), to: Vec2(900, 190 + reach), forward: Vec2(-1, 0)),
            // The hairpin apex gate, ACROSS the tip (not behind it): a car
            // only crosses it heading outward (+x) once it has actually
            // rounded the far end near x≈980 — cutting the neck straight
            // across to the return lane travels −x and never trips it, so
            // the loop must be driven. Reaches out to the wall so running
            // wide over grass at the tip still counts (grass is the penalty).
            Gate(from: Vec2(960, 500), to: Vec2(960, 700), forward: Vec2(1, 0)),
            Gate(
                from: Vec2(760, 745), to: Vec2(760, size.y - wall),
                forward: Vec2(1, 0)),
        ]

        return Track(
            id: "hairpin",
            centerline: points,
            width: width,
            walls: boundaryWalls(size: size),
            gates: gates,
            patches: [
                // Mud guards the hairpin entry, oil the flat-out top
                // straight, water the corner onto the right side.
                SurfacePatch(center: Vec2(700, 578), radius: 42, surface: .mud),
                SurfacePatch(center: Vec2(820, 190), radius: 30, surface: .oil),
                SurfacePatch(center: Vec2(1350, 660), radius: 42, surface: .water),
            ],
            startSlots: (0..<4).map { i in
                Vec2(690 - Double(i) * 50, 820 + (i % 2 == 0 ? -28 : 28))
            },
            startHeading: 0,
            size: size,
            pit: Vec2(760, 360)  // infield of the bowl, clear of every lane
        )
    }

    private static func hairpinCenterline() -> [Vec2] {
        var points: [Vec2] = []
        func arc(center: Vec2, radius: Double, from: Double, to: Double, steps: Int = 6) {
            for i in 0...steps {
                let angle = from + (to - from) * Double(i) / Double(steps)
                points.append(center + Vec2(angle: angle) * radius)
            }
        }
        // Bottom straight L→R.
        points.append(Vec2(350, 820))
        points.append(Vec2(1180, 820))
        // Bottom-right corner, up the right side.
        arc(center: Vec2(1180, 650), radius: 170, from: .pi / 2, to: 0)
        points.append(Vec2(1350, 360))
        arc(center: Vec2(1180, 360), radius: 170, from: 0, to: -.pi / 2)
        // Top straight R→L.
        points.append(Vec2(640, 190))
        arc(center: Vec2(640, 360), radius: 170, from: -.pi / 2, to: -.pi)
        // Down, then dive right into the peninsula.
        points.append(Vec2(470, 480))
        points.append(Vec2(900, 520))
        // The hairpin itself.
        arc(center: Vec2(900, 600), radius: 80, from: -.pi / 2, to: .pi / 2)
        // Back out along the return lane.
        points.append(Vec2(620, 680))
        points.append(Vec2(430, 700))
        points.append(Vec2(355, 760))
        return points
    }
}
