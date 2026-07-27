import SkidCore
import SwiftUI

/// Car and deck-rail drawing, split out of TrackRenderer to keep each file
/// within the length budget. Everything here draws in world space, inside the
/// aspect-fit transform set up by `TrackRenderer.draw`.
extension TrackRenderer {
    static func drawCars(
        scene: WorldScene, gateChrome: GateChrome, colorAt: (Int) -> Color,
        into context: inout GraphicsContext
    ) {
        let race = scene.race
        let track = race.track
        let translucent = ghostOverlaps(race: race)
        // The PB ghost drives under the real cars, translucent and
        // colorless — present, never in the way.
        for ghost in scene.ghosts where !ghost.isAirborne {
            draw(car: ghost, color: .white, opacity: 0.38, into: &context)
        }
        // A car climbing a ramp draws ABOVE the deck, so its nose never slides
        // under the bridge edge on the way up.
        //
        // It must be ON the ramp, not merely near one: asking only "is there
        // sloped road at this spot" was true for a car on the grass beside a ramp
        // and for one on the road passing under the bridge, so those were promoted
        // into the elevated pass and drawn up on the deck. The debug overlay caught
        // it — a car reading "h 0.00 / grass / off road 101" drawn on the bridge.
        //
        // Which pass a car draws in follows its HEIGHT alone, because the
        // ribbon bands PARTITION at the same boundary: at or below the
        // half-level shelf a car stands on ground-band road (drawn before
        // ground cars), above it on elevated-band road (drawn before elevated
        // cars). The old scheme promoted "climbing" cars between groups by
        // sniffing for nearby slopes, and both of its failure modes shipped:
        // a ground car under the bridge sniffed the ramp's eased foot and rode
        // on top, then the fix for that left a real climber buried under the
        // foot piece's second copy — which existed only because the bands
        // OVERLAPPED at exactly 0.5.
        func onGround(_ car: Car) -> Bool { car.state.height <= 0.5 }
        for (index, car) in race.cars.enumerated()
        where onGround(car) && !car.state.isAirborne {
            draw(
                car: car.state, color: colorAt(index),
                opacity: translucent.contains(index) ? 0.55 : 1,
                into: &context
            )
        }

        if track.heights.contains(where: { $0 > 0.5 }) {
            // NOW the bridge, on top of the ground cars just drawn — that
            // ordering is what hides a car driving underneath it. Same shared
            // renderer as the editor, just the upper height band.
            if let layout = track.layout {
                // The race's gate display is the white chrome — no editor
                // markers here either (they were also a seam off).
                // 0.75, not 0.5: piece heights sit on the half-level
                // lattice, so maxima are 0, 0.5 or 1 — and 0.5 belonged to BOTH
                // bands, double-drawing every climb's lower half over the cars
                // on it. Anything that stays at or below the shelf is ground.
                EditorRenderer.drawTrack(
                    walk: layout.walk(), width: track.width, gateSeams: [],
                    transform: track.layoutTransform, heightRange: 0.75...2, into: &context)
            } else {
                drawRibbon(track: track, elevated: true, into: &context)
            }
            drawGates(gateChrome, elevated: true, into: &context)
            // Rubber laid on the deck, over the deck's ribbon — ground marks
            // went down before the bridge, so each level keeps its own.
            drawMarks(scene.marks, elevated: true, into: &context)
            //
            // Never-invisible rule: a ground car hidden under the bridge
            // shows through as a bubble in its color. Ramp climbers are
            // fully visible on their slope — no bubble.
            for (index, car) in race.cars.enumerated()
            where onGround(car)
                && track.distanceToCenterline(car.state.position, height: 1)
                    < track.width / 2 + 8
            {
                drawBubble(at: car.state.position, color: colorAt(index), into: &context)
            }
            // Bridge cars, and ramp climbers on their way up/down: scaled
            // SMOOTHLY by the continuous height at their position (the same
            // Elevation.scale factor the road width uses), so a car grows as it
            // climbs and reads as elevated on the deck — no discrete pop.
            for (index, car) in race.cars.enumerated()
            where !car.state.isAirborne && !onGround(car) {
                // The car's own height IS the scale now — no reconstruction.
                draw(
                    car: car.state, color: colorAt(index),
                    scale: Elevation.scale(atHeight: car.state.height), into: &context)
            }
        }

        // Airborne cars fly over everything: bigger, with a drop shadow.
        for (index, car) in race.cars.enumerated() where car.state.isAirborne {
            draw(
                car: car.state, color: colorAt(index), scale: 1.22, shadow: true,
                into: &context)
        }
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
