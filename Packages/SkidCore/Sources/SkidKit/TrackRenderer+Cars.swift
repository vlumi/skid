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
        // A car on a ramp slope draws ABOVE the deck, so its nose never slides
        // under the bridge edge on the way up.
        func onRamp(_ car: Car) -> Bool { track.isOnRamp(car.state.position) }
        // "On the ground" is now a height comparison, not a layer test.
        func onGround(_ car: Car) -> Bool { car.state.height <= 0.5 }
        for (index, car) in race.cars.enumerated()
        where onGround(car) && !car.state.isAirborne && !onRamp(car) {
            draw(
                car: car.state, color: colorAt(index),
                opacity: translucent.contains(index) ? 0.55 : 1,
                into: &context
            )
        }

        if track.heights.contains(where: { $0 > 0.5 }) {
            drawRibbon(track: track, elevated: true, into: &context)
            drawDeckRails(track: track, into: &context)
            drawGates(gateChrome, elevated: true, into: &context)
            // Never-invisible rule: a ground car hidden under the bridge
            // shows through as a bubble in its color. Ramp climbers are
            // fully visible on their slope — no bubble.
            for (index, car) in race.cars.enumerated()
            where onGround(car) && !onRamp(car)
                && track.distanceToCenterline(car.state.position, height: 1)
                    < track.width / 2 + 8
            {
                let p = car.state.position
                let bubble = CGRect(x: p.x - 15, y: p.y - 15, width: 30, height: 30)
                context.fill(
                    Path(ellipseIn: bubble), with: .color(colorAt(index).opacity(0.55)))
                context.stroke(
                    Path(ellipseIn: bubble), with: .color(.white.opacity(0.85)), lineWidth: 2.5)
            }
            // Bridge cars, and ramp climbers on their way up/down: scaled
            // SMOOTHLY by the continuous height at their position (the same
            // Elevation.scale factor the road width uses), so a car grows as it
            // climbs and reads as elevated on the deck — no discrete pop.
            for (index, car) in race.cars.enumerated()
            where !car.state.isAirborne && (!onGround(car) || onRamp(car)) {
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

    /// Retaining rails along the bridge deck — drawn to look **identical to the
    /// editor's**, since it's the same barrier and should read as the same object
    /// whether you're building it or driving it.
    ///
    /// Matching means four things, not just the color: the same `bridgeRail` blue
    /// over a dark base, the same world-space band widths (12+5 under 12+2), butt
    /// caps with round joins, and — most visibly — each side stroked as ONE
    /// CONTINUOUS POLYLINE. Stroking wall segments individually with round caps
    /// beaded them into a lumpy chain of blobs at every joint.
    ///
    /// Layer-1 walls only. A ramp also emits layer-0 rails so a ground car can't
    /// drive up its flank; those are the same barrier seen from below, already
    /// drawn by their layer-1 twin.
    private static func drawDeckRails(track: Track, into context: inout GraphicsContext) {
        var rails = Path()
        for run in railRuns(track.walls.filter { $0.kind == .rail && $0.height > 0.05 }) {
            guard let first = run.first else { continue }
            rails.move(to: CGPoint(x: first.x, y: first.y))
            for point in run.dropFirst() {
                rails.addLine(to: CGPoint(x: point.x, y: point.y))
            }
        }
        guard !rails.isEmpty else { return }
        let band = 12.0
        context.stroke(
            rails, with: .color(.black.opacity(0.5)),
            style: StrokeStyle(lineWidth: band + 5, lineCap: .butt, lineJoin: .round))
        context.stroke(
            rails, with: .color(bridgeRail),
            style: StrokeStyle(lineWidth: band + 2, lineCap: .butt, lineJoin: .round))
    }

    /// Chain wall segments back into continuous polylines by joining ends that
    /// meet. The compiler emits a rail as many short segments (one per geometry
    /// sample); this recovers the runs so they can be stroked as single paths,
    /// the way the editor does from its own sample arrays.
    private static func railRuns(_ walls: [Wall]) -> [[Vec2]] {
        var remaining = walls
        var runs: [[Vec2]] = []
        while let seed = remaining.popLast() {
            var run = [seed.a, seed.b]
            // Extend from both ends until nothing else connects.
            var grew = true
            while grew {
                grew = false
                for (index, wall) in remaining.enumerated() {
                    let tail = run[run.count - 1]
                    let head = run[0]
                    if (wall.a - tail).length < 0.5 {
                        run.append(wall.b)
                    } else if (wall.b - tail).length < 0.5 {
                        run.append(wall.a)
                    } else if (wall.b - head).length < 0.5 {
                        run.insert(wall.a, at: 0)
                    } else if (wall.a - head).length < 0.5 {
                        run.insert(wall.b, at: 0)
                    } else {
                        continue
                    }
                    remaining.remove(at: index)
                    grew = true
                    break
                }
            }
            runs.append(run)
        }
        return runs
    }

    /// The bridge guard rail, matching the editor's palette exactly.
    static let bridgeRail = Color(red: 0.55, green: 0.78, blue: 0.95)

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
