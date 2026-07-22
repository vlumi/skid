import Foundation

extension TrackLibrary {
    /// "Gauntlet": the rounded rectangle pinched on BOTH straights, on a
    /// narrower ribbon — two chicanes per lap and hazards guarding each.
    /// Start/finish sits on the right half of the bottom straight, clear of
    /// the bottom pinch.
    public static func gauntlet() -> Track {
        let size = Vec2(1600, 1000)
        let width = 112.0
        let cx = 800.0
        let cy = 500.0
        let top = 200.0
        let bottom = 800.0
        let left = 240.0
        let right = 1360.0

        let points = gauntletCenterline(
            cx: cx, top: top, bottom: bottom, left: left, right: right)
        let wall = 8.0
        let reach = width / 2 + 150
        let gates = [
            Gate(from: Vec2(right - reach, cy), to: Vec2(size.x - wall, cy), forward: Vec2(0, -1)),
            Gate(from: Vec2(cx, wall), to: Vec2(cx, top + 130 + reach), forward: Vec2(-1, 0)),
            Gate(from: Vec2(wall, cy), to: Vec2(left + reach, cy), forward: Vec2(0, 1)),
            Gate(
                from: Vec2(1000, bottom - reach), to: Vec2(1000, size.y - wall),
                forward: Vec2(1, 0)),
        ]

        return Track(
            id: "gauntlet",
            centerline: points,
            width: width,
            walls: boundaryWalls(size: size),
            gates: gates,
            patches: [
                // The pinches bite: oil on the top pinch exit, mud filling
                // the bottom pinch apex, water on the right straight.
                SurfacePatch(center: Vec2(cx - 210, top + 30), radius: 32, surface: .oil),
                SurfacePatch(center: Vec2(580, bottom - 60), radius: 48, surface: .mud),
                SurfacePatch(center: Vec2(right - 24, cy - 130), radius: 44, surface: .water),
            ],
            startSlots: (0..<4).map { i in
                Vec2(930 - Double(i) * 50, bottom + (i % 2 == 0 ? -28 : 28))
            },
            startHeading: 0,
            size: size,
            pit: Vec2(800, 550)  // infield center, clear of both straights
        )
    }

    private static func gauntletCenterline(
        cx: Double, top: Double, bottom: Double, left: Double, right: Double
    ) -> [Vec2] {
        let corner = 170.0
        var points: [Vec2] = []
        func arc(center: Vec2, from: Double, to: Double, steps: Int = 6) {
            for i in 0...steps {
                let angle = from + (to - from) * Double(i) / Double(steps)
                points.append(center + Vec2(angle: angle) * corner)
            }
        }
        // Bottom straight L→R, dipping into the bottom pinch on its left half.
        points.append(Vec2(left + corner, bottom))
        points.append(Vec2(470, bottom))
        points.append(Vec2(540, bottom - 128))
        points.append(Vec2(620, bottom - 128))
        points.append(Vec2(690, bottom))
        points.append(Vec2(right - corner, bottom))
        arc(center: Vec2(right - corner, bottom - corner), from: .pi / 2, to: 0)
        points.append(Vec2(right, top + corner))
        arc(center: Vec2(right - corner, top + corner), from: 0, to: -.pi / 2)
        // Top straight R→L with the top pinch, mirroring the practice loop.
        points.append(Vec2(cx + 190, top))
        points.append(Vec2(cx + 60, top + 130))
        points.append(Vec2(cx - 60, top + 130))
        points.append(Vec2(cx - 190, top))
        arc(center: Vec2(left + corner, top + corner), from: -.pi / 2, to: -.pi)
        points.append(Vec2(left, bottom - corner))
        arc(center: Vec2(left + corner, bottom - corner), from: .pi, to: .pi / 2)
        return points
    }
}
