import Foundation

extension TrackLibrary {
    /// "Overpass": the figure-eight — two lobes crossing in the middle,
    /// one diagonal carried over the other on a bridge. Ramps lift the car
    /// onto the elevated span and back down; the bridge carries its own
    /// gate (on layer 1), so the overpass route must actually be driven.
    /// Straying off the bridge edge drops the car back to the ground.
    public static func overpass() -> Track {
        let size = Vec2(1600, 1000)
        let width = 110.0
        let points = overpassCenterline()
        // The elevated span is the single long NE→SW diagonal segment
        // between (950,190) and (700,760).
        let diveStart = Vec2(950, 190)
        let diveEnd = Vec2(700, 760)
        let elevated = Set([points.firstIndex(of: diveStart) ?? 0])
        let diveDirection = (diveEnd - diveStart).normalized
        let across = diveDirection.perpendicular

        func rampLine(at t: Double) -> (Vec2, Vec2) {
            let center = diveStart + (diveEnd - diveStart) * t
            let half = across * (width / 2 + 26)
            return (center - half, center + half)
        }
        let up = rampLine(at: 0.1)
        let down = rampLine(at: 0.9)
        let bridgeGateLine = rampLine(at: 0.5)

        return Track(
            id: "overpass",
            centerline: points,
            width: width,
            elevatedSegments: elevated,
            ramps: [
                Ramp(from: up.0, to: up.1, forward: diveDirection),
                Ramp(from: down.0, to: down.1, forward: diveDirection),
            ],
            walls: boundaryWalls(size: size),
            gates: overpassGates(
                size: size, width: width, bridgeGateLine: bridgeGateLine,
                diveDirection: diveDirection),
            patches: [
                SurfacePatch(center: Vec2(1320, 700), radius: 40, surface: .water),
                SurfacePatch(center: Vec2(365, 275), radius: 42, surface: .mud),
                SurfacePatch(center: Vec2(560, 815), radius: 30, surface: .oil),
            ],
            startSlots: (0..<4).map { i in
                Vec2(1040 - Double(i) * 45, 810 + (i % 2 == 0 ? -26 : 26))
            },
            startHeading: 0,
            size: size
        )
    }

    private static func overpassGates(
        size: Vec2, width: Double, bridgeGateLine: (Vec2, Vec2), diveDirection: Vec2
    ) -> [Gate] {
        let wall = 8.0
        return [
            // Right side of the right lobe, driving up.
            Gate(
                from: Vec2(1320 - width / 2 - 130, 500), to: Vec2(size.x - wall, 500),
                forward: Vec2(0, -1)),
            // Mid-bridge, elevated — the crossing that must be earned.
            Gate(
                from: bridgeGateLine.0, to: bridgeGateLine.1, forward: diveDirection,
                layer: 1),
            // Left side of the left lobe, also driving up (the 8-ness).
            Gate(
                from: Vec2(wall, 500), to: Vec2(280 + width / 2 + 130, 500),
                forward: Vec2(0, -1)),
            // Mid flat diagonal, under the bridge.
            Gate(
                from: Vec2(755 - 90, 483), to: Vec2(755 + 90, 483),
                forward: Vec2(200, 555).normalized),
            // Start/finish on the bottom-right straight.
            Gate(
                from: Vec2(1090, 810 - width / 2 - 110), to: Vec2(1090, size.y - wall),
                forward: Vec2(1, 0)),
        ]
    }

    private static func overpassCenterline() -> [Vec2] {
        var points: [Vec2] = []
        func arc(center: Vec2, radius: Double, from: Double, to: Double, steps: Int = 6) {
            for i in 0...steps {
                let angle = from + (to - from) * Double(i) / Double(steps)
                points.append(center + Vec2(angle: angle) * radius)
            }
        }
        // Bottom-right straight, driving right.
        points.append(Vec2(870, 810))
        points.append(Vec2(1150, 810))
        // Around the right lobe: up the right side, across its top.
        arc(center: Vec2(1150, 640), radius: 170, from: .pi / 2, to: 0)
        points.append(Vec2(1320, 360))
        arc(center: Vec2(1150, 360), radius: 170, from: 0, to: -.pi / 2)
        // Dive over the bridge: one long elevated diagonal to the left lobe.
        points.append(Vec2(950, 190))
        points.append(Vec2(700, 760))
        // Left lobe: bottom, up the left side, across its top.
        points.append(Vec2(650, 810))
        points.append(Vec2(450, 810))
        arc(center: Vec2(450, 640), radius: 170, from: .pi / 2, to: .pi)
        points.append(Vec2(280, 360))
        arc(center: Vec2(450, 360), radius: 170, from: .pi, to: 3 * .pi / 2)
        points.append(Vec2(650, 190))
        // The flat diagonal back down under the bridge, closing the eight.
        points.append(Vec2(850, 745))
        return points
    }
}
