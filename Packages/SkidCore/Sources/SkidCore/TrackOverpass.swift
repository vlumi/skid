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
        // The dive is three segments: a sloped approach (ground), the
        // elevated deck, and a sloped descent (ground). The car changes
        // layer exactly where the deck begins/ends — the slopes are real
        // road it drives up, not a warp.
        let diveStart = Vec2(950, 190)
        let deckStart = Vec2(905, 293)
        let deckEnd = Vec2(745, 657)
        let diveEnd = Vec2(700, 760)
        let approachIndex = points.firstIndex(of: diveStart) ?? 0
        let deckIndex = points.firstIndex(of: deckStart) ?? 0
        let descentIndex = points.firstIndex(of: deckEnd) ?? 0
        let diveDirection = (diveEnd - diveStart).normalized
        let across = diveDirection.perpendicular

        func line(at point: Vec2) -> (Vec2, Vec2) {
            // Slightly NARROWER than the deck ribbon: any crossing then
            // lands safely inside the deck's fall-off tolerance — a car
            // hugging the retaining wall can't flip layers and instantly
            // fall off the edge (the reverse-onto-the-bridge bubble bug).
            // The walls funnel every possible crossing within this span.
            let half = across * (width / 2 - 2)
            return (point - half, point + half)
        }
        let up = line(at: deckStart)
        let down = line(at: deckEnd)
        let bridgeGateLine = line(at: (deckStart + deckEnd) * 0.5)

        let walls = overpassWalls(
            size: size, width: width, across: across,
            dive: Dive(start: diveStart, deckStart: deckStart, deckEnd: deckEnd, end: diveEnd))

        return Track(
            id: "overpass",
            centerline: points,
            width: width,
            elevatedSegments: [deckIndex],
            rampSegments: [approachIndex, descentIndex],
            ramps: [
                // Up: ground → deck at the deck's start.
                Ramp(from: up.0, to: up.1, forward: diveDirection),
                // Down: deck → ground at the deck's end (forward descends;
                // crossing it backward climbs back up).
                Ramp(
                    from: down.0, to: down.1, forward: diveDirection,
                    fromLayer: 1, toLayer: 0),
            ],
            walls: walls,
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
            size: size,
            pit: Vec2(1040, 550)  // right-lobe infield, by the start/finish
        )
    }

    /// Boundary + ramp retaining walls (layer 0) plus deck rails (layer 1).
    /// The deck rails keep reaching the mid-bridge checkpoint from being a
    /// tightrope: a car that drifts wide up top is caught, not dropped. Being
    /// layer-specific, the road running underneath passes straight through
    /// them; they cover the span's middle and stop short of the ramp mouths.
    /// The four points of the dive, in drive order: ground → deck start →
    /// deck end → ground.
    private struct Dive {
        var start: Vec2
        var deckStart: Vec2
        var deckEnd: Vec2
        var end: Vec2
    }

    private static func overpassWalls(
        size: Vec2, width: Double, across: Vec2, dive: Dive
    ) -> [Wall] {
        boundaryWalls(size: size)
            + rampWalls(ground: dive.start, deck: dive.deckStart, width: width)
            + rampWalls(ground: dive.end, deck: dive.deckEnd, width: width)
            + deckWalls(
                deckStart: dive.deckStart, deckEnd: dive.deckEnd, across: across, width: width)
    }

    /// Retaining walls along a ramp's sides: a ramp is entered from the
    /// connecting road below or from the deck above — never sideways. The
    /// walls follow the ramp axis and hold a constant half-width the whole
    /// way, so the wall edge lines up with the ribbon edge at both ends
    /// (the old splay from width/2 to width/2+8 left the top端 flaring off
    /// the deck edge). They stop just short of the deck so they don't jut
    /// into the road that runs underneath at the ramp foot.
    private static func rampWalls(ground: Vec2, deck: Vec2, width: Double) -> [Wall] {
        let axis = (deck - ground).normalized
        let side = axis.perpendicular
        let half = width / 2
        // Pull the top end back a touch so the descent ramp's walls don't
        // overlap the flat road passing beneath the deck's foot.
        let top = deck - axis * 14
        return [-1.0, 1.0].map { sign in
            Wall(from: ground + side * (half * sign), to: top + side * (half * sign))
        }
    }

    /// Layer-1 retaining walls down the two edges of the bridge deck,
    /// covering its middle and stopping short of each ramp mouth. Only
    /// elevated cars (layer 1) collide with these; the ground road under the
    /// bridge is unaffected.
    private static func deckWalls(
        deckStart: Vec2, deckEnd: Vec2, across: Vec2, width: Double
    ) -> [Wall] {
        // Leave the first/last fifth of the span open for the ramp mouths.
        let a = deckStart + (deckEnd - deckStart) * 0.2
        let b = deckStart + (deckEnd - deckStart) * 0.8
        let half = across * (width / 2)
        return [-1.0, 1.0].map { sign in
            Wall(from: a + half * sign, to: b + half * sign, layer: 1)
        }
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
        // The dive: sloped approach, elevated deck, sloped descent.
        points.append(Vec2(950, 190))
        points.append(Vec2(905, 293))
        points.append(Vec2(745, 657))
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
