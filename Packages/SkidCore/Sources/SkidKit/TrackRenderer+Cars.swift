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
        // A car on a ramp slope is transitioning between layers: it draws
        // ABOVE the deck (else its nose slides under the bridge edge and
        // the car "warps" on top when the layer flips mid-car).
        func onRamp(_ car: Car) -> Bool {
            !track.rampSegments.isEmpty && track.isOnRamp(car.state.position)
        }
        for (index, car) in race.cars.enumerated()
        where car.state.layer == 0 && !car.state.isAirborne && !onRamp(car) {
            draw(
                car: car.state, color: colorAt(index),
                opacity: translucent.contains(index) ? 0.55 : 1,
                into: &context
            )
        }

        if !track.elevatedSegments.isEmpty {
            drawRibbon(track: track, layer: 1, into: &context)
            drawDeckRails(track: track, into: &context)
            drawGates(gateChrome, layerFilter: 1, into: &context)
            // Never-invisible rule: a ground car hidden under the bridge
            // shows through as a bubble in its color. Ramp climbers are
            // fully visible on their slope — no bubble.
            for (index, car) in race.cars.enumerated()
            where car.state.layer == 0 && !onRamp(car)
                && track.distanceToCenterline(car.state.position, layer: 1)
                    < track.width / 2 + 8
            {
                let p = car.state.position
                let bubble = CGRect(x: p.x - 15, y: p.y - 15, width: 30, height: 30)
                context.fill(
                    Path(ellipseIn: bubble), with: .color(colorAt(index).opacity(0.55)))
                context.stroke(
                    Path(ellipseIn: bubble), with: .color(.white.opacity(0.85)), lineWidth: 2.5)
            }
            // Bridge cars, and ramp climbers on their way up/down.
            for (index, car) in race.cars.enumerated()
            where !car.state.isAirborne && (car.state.layer == 1 || onRamp(car)) {
                draw(car: car.state, color: colorAt(index), into: &context)
            }
        }

        // Airborne cars fly over everything: bigger, with a drop shadow.
        for (index, car) in race.cars.enumerated() where car.state.isAirborne {
            draw(
                car: car.state, color: colorAt(index), scale: 1.22, shadow: true,
                into: &context)
        }
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

    /// Retaining rails along the bridge deck (the layer-1 walls). Drawn as a
    /// raised barrier — a dark base plus a lighter cap — so the edge that
    /// catches a wide car up top reads clearly against the deck.
    private static func drawDeckRails(track: Track, into context: inout GraphicsContext) {
        for wall in track.walls where wall.layer == 1 {
            var rail = Path()
            rail.move(to: CGPoint(x: wall.a.x, y: wall.a.y))
            rail.addLine(to: CGPoint(x: wall.b.x, y: wall.b.y))
            context.stroke(
                rail, with: .color(.black.opacity(0.4)),
                style: StrokeStyle(lineWidth: 8, lineCap: .round))
            context.stroke(
                rail, with: .color(Color(white: 0.85)),
                style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
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
        // Narrow open-wheeler body: a capsule nose-to-tail. A TWO-TONE outline
        // wraps it — a light ring just outside a dark ring — so one of the two
        // always contrasts whatever's underneath: a dark car in the dark mud,
        // or a light car on pale asphalt, both stay legible. Background-
        // independent by construction (no fixed tint could do it alone), which
        // is what carries the car onto the map themes to come.
        let body = CGRect(x: -length / 2, y: -width / 4, width: length, height: width / 2)
        let bodyPath = Path(roundedRect: body, cornerRadius: width / 4)
        let lightRing = Path(
            roundedRect: body.insetBy(dx: -2.5, dy: -2.5), cornerRadius: width / 4 + 2.5)
        car2D.stroke(lightRing, with: .color(.white.opacity(0.85)), lineWidth: 2)
        car2D.fill(bodyPath, with: .color(color))
        car2D.stroke(bodyPath, with: .color(.black.opacity(0.7)), lineWidth: 1.5)
        // Cockpit dot behind the midpoint.
        let cockpit = CGRect(x: -4, y: -3.2, width: 6.4, height: 6.4)
        car2D.fill(Path(ellipseIn: cockpit), with: .color(.black.opacity(0.65)))
    }
}
