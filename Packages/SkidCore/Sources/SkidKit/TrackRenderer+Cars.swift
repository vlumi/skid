import SkidCore
import SwiftUI

/// Car and deck-rail drawing, split out of TrackRenderer to keep each file
/// within the length budget. Everything here draws in world space, inside the
/// aspect-fit transform set up by `TrackRenderer.draw`.
extension TrackRenderer {
    /// Collect the cars as layers: each one at the storey it occupies, so the
    /// z-order puts it above its own road and under any road a level above.
    ///
    /// No pass-picking. A car on ASPHALT is at the storey of the piece under
    /// it — the ribbon paints whole at the level of its highest end, so the car
    /// must stack by the same rule, or mid-climb it is a storey below its own
    /// road and vanishes beneath the ramp's upper half. A car on GRASS has no
    /// piece; its raw height decides (which is what hides it under a bridge,
    /// where the bubble takes over). The long-running "is this car on a ramp /
    /// over ground-height road?" promotion logic is still gone — this is a
    /// lookup of stored piece data, not a guess from nearby slopes.
    static func addCars(
        scene: WorldScene, gateChrome: GateChrome, colorAt: @escaping (Int) -> Color,
        to order: inout RenderOrder.Builder
    ) {
        let race = scene.race
        let track = race.track
        let translucent = ghostOverlaps(race: race)

        // The PB ghost drives under the real cars, translucent and colorless —
        // present, never in the way.
        for ghost in scene.ghosts where !ghost.isAirborne {
            order.add(storey: carStorey(of: ghost, on: track), kind: .car) { context in
                draw(car: ghost, color: .white, opacity: 0.38, into: &context)
            }
        }

        for (index, car) in race.cars.enumerated() where !car.state.isAirborne {
            let state = car.state
            let opacity = translucent.contains(index) ? 0.55 : 1
            let storey = carStorey(of: state, on: track)
            order.add(storey: storey, kind: .car) { context in
                // Scaled by the continuous height at its position (the same
                // Elevation.scale the road width uses), so a car grows as it
                // climbs — no discrete pop at a level boundary.
                draw(
                    car: state, color: colorAt(index), opacity: opacity,
                    scale: Elevation.scale(atHeight: state.height), into: &context)
            }
            // Never-invisible rule: a car with road a full level above it is
            // hidden by that road, so it also shows through as a bubble in its
            // own color. Drawn at the covering storey, above that road.
            let coveringStorey = storey + 1
            let coveringHeight = Double(coveringStorey) * Track.levelHeight
            if track.heights.contains(where: { Track.level(of: $0) == coveringStorey }),
                track.distanceToCenterline(state.position, height: coveringHeight)
                    < track.width / 2 + 8
            {
                order.add(storey: coveringStorey, kind: .car) { context in
                    drawBubble(at: state.position, color: colorAt(index), into: &context)
                }
            }
        }

        // Airborne cars fly over everything: bigger, with a drop shadow.
        for (index, car) in race.cars.enumerated() where car.state.isAirborne {
            let state = car.state
            order.add(storey: Track.highestLevel + 1, kind: .airborne) { context in
                draw(
                    car: state, color: colorAt(index), scale: 1.22, shadow: true,
                    into: &context)
            }
        }
    }

    /// The storey a car paints in: on asphalt, the storey of the piece it is
    /// ON (via the stored deck tops); on grass, the storey of its own height.
    static func carStorey(of state: CarState, on track: Track) -> Int {
        guard
            track.distanceToCenterline(state.position, height: state.height)
                <= track.width / 2
        else { return Track.level(of: state.height) }
        return storey(ofTop: track.deckTop(at: state.position, preferHeight: state.height))
    }

    /// A car hidden under the bridge, shown through it in its own color, so no
    /// player is ever invisible.
    private static func drawBubble(
        at position: Vec2, color: Color, into context: inout GraphicsContext
    ) {
        let bubble = CGRect(x: position.x - 15, y: position.y - 15, width: 30, height: 30)
        context.fill(Path(ellipseIn: bubble), with: .color(color.opacity(0.55)))
        context.stroke(
            Path(ellipseIn: bubble), with: .color(.white.opacity(0.85)), lineWidth: 2.5)
    }

    /// Ghost mode: overlapping pass-through cars go translucent so pileups
    /// on the racing line stay readable.
    private static func ghostOverlaps(race: Race) -> Set<Int> {
        var translucent: Set<Int> = []
        guard !race.config.carContact else { return translucent }
        for i in 0..<race.cars.count {
            for j in (i + 1)..<race.cars.count {
                let gap = race.cars[i].state.position.distance(
                    to: race.cars[j].state.position)
                if gap < CarGeometry.radius * 2.6 {
                    translucent.insert(i)
                    translucent.insert(j)
                }
            }
        }
        return translucent
    }

    private static func draw(
        car: CarState, color: Color, opacity: Double = 1, scale: Double = 1,
        shadow: Bool = false, into context: inout GraphicsContext
    ) {
        if shadow {
            // A soft blob on the ground below a flying car.
            let rect = CGRect(
                x: car.position.x - 16 + 9, y: car.position.y - 11 + 15, width: 32, height: 22)
            context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.25)))
        }
        var car2D = context
        car2D.opacity = opacity
        car2D.translateBy(x: car.position.x, y: car.position.y)
        car2D.rotate(by: Angle(radians: car.heading))
        car2D.scaleBy(x: scale, y: scale)

        let length = CarGeometry.length
        let width = CarGeometry.width
        // A headlight cone projected AHEAD of the nose, in the car's tint:
        // a soft fan that fades out, reading the facing direction at a glance
        // (even mid-flip, where nose ≠ travel) without shouting like the old
        // bold arrow. Skipped for the translucent PB ghost.
        if opacity > 0.5 {
            let mouth = length / 2 + 2  // just off the nose
            let reach = mouth + 46  // how far the beam throws
            let spread = 20.0  // half-width of the beam at its far end
            var cone = Path()
            cone.move(to: CGPoint(x: mouth, y: -3))
            cone.addLine(to: CGPoint(x: reach, y: -spread))
            cone.addLine(to: CGPoint(x: reach, y: spread))
            cone.addLine(to: CGPoint(x: mouth, y: 3))
            cone.closeSubpath()
            // Fade along the throw so it glows from the nose and dissolves.
            car2D.fill(
                cone,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.55), color.opacity(0)]),
                    startPoint: CGPoint(x: mouth, y: 0), endPoint: CGPoint(x: reach, y: 0)))
        }
        // Tires first, so the body sits on top; open-wheel means they stick
        // out past the body sides.
        for offset in CarGeometry.tireOffsets {
            let tire = CGRect(x: offset.x - 4.5, y: offset.y - 3, width: 9, height: 6)
            car2D.fill(Path(roundedRect: tire, cornerRadius: 2), with: .color(rubber))
        }
        // Narrow open-wheeler body: a capsule nose-to-tail. The look is a bold
        // dark rim (the cartoony edge that reads well on grass/asphalt). A soft
        // light GLOW sits just outside that edge — subtler and closer than the
        // headlight — barely there on light surfaces, but enough to keep a dark
        // car legible on dark ground (the mud pit), where a dark-only edge
        // would vanish. Background-independent, and carries onto map themes.
        let body = CGRect(x: -length / 2, y: -width / 4, width: length, height: width / 2)
        let bodyPath = Path(roundedRect: body, cornerRadius: width / 4)
        // The glow: the dark rim drawn into a layer with TWO stacked white
        // shadow filters, so a soft light aura bleeds out around the whole
        // silhouette. Stacking compounds the light so it stays visible even at
        // the tiny on-device car size (a single pass all but vanished).
        car2D.drawLayer { glow in
            glow.addFilter(.shadow(color: .white.opacity(0.9), radius: 4))
            glow.addFilter(.shadow(color: .white.opacity(0.9), radius: 4))
            glow.stroke(bodyPath, with: .color(.black.opacity(0.7)), lineWidth: 2)
        }
        car2D.fill(bodyPath, with: .color(color))
        car2D.stroke(bodyPath, with: .color(.black.opacity(0.7)), lineWidth: 2)
        // Cockpit dot behind the midpoint.
        let cockpit = CGRect(x: -4, y: -3.2, width: 6.4, height: 6.4)
        car2D.fill(Path(ellipseIn: cockpit), with: .color(.black.opacity(0.65)))
    }
}
