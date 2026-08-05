import SkidCore
import SwiftUI

/// Draws what the **simulation** believes, on top of what the renderer drew.
///
/// This exists because every elevation bug in this area came down to the drawing
/// and the physics disagreeing — a track rendered where it wasn't, a rail placed
/// where the car couldn't reach, a car taking height from road it wasn't on. Those
/// are invisible in a screenshot and awkward to catch in a test, because the test
/// has to guess which of the two is wrong. Seeing both at once, while driving,
/// settles it immediately.
///
/// Everything here reads sim state and draws; nothing feeds back.
enum DebugOverlay {
    /// The sim's centerline, its height ramp, walls, gates, and per-car readouts.
    /// **The wall-contact readout**, for player 1's car — a plain box in the corner.
    ///
    /// Screen space, not world space, so it stays put and legible however the map is
    /// scaled; and drawn from HELD figures (see `CarState.WallContact`) because a
    /// tick is 1/60 s and no screenshot can be timed to one.
    public static func drawWallReadout(
        _ race: Race, in size: CGSize, into context: inout GraphicsContext
    ) {
        guard let car = race.cars.first else { return }
        let w = car.state.wallContact
        let speed = car.state.velocity.length
        let kept =
            w.speedAtStart > 1 ? "\(Int(speed / w.speedAtStart * 100))%" : "—"
        let lines: [(String, String)] = [
            ("speed", "\(Int(speed))"),
            ("slip", "\(Int(car.state.slipSpeed))"),
            ("", ""),
            ("contact ticks", w.ticks > 0 ? "\(w.ticks)" : "—"),
            ("hits this tick", "\(w.hits)"),
            ("press", "\(Int(w.press))"),
            ("squareness", String(format: "%.2f", w.squareness)),
            ("slide", "\(Int(w.slide))"),
            ("", ""),
            ("lost this tick", String(format: "%.1f", w.speedLost)),
            ("worst tick", String(format: "%.1f", w.worstLoss)),
            ("lost in run", "\(Int(w.totalLoss))"),
            ("kept of start", kept),
        ]
        let lineHeight = 15.0
        let boxWidth = 168.0
        let boxHeight = Double(lines.count) * lineHeight + 12
        let origin = CGPoint(x: 8, y: size.height - boxHeight - 8)
        context.fill(
            Path(
                roundedRect: CGRect(
                    x: origin.x, y: origin.y, width: boxWidth, height: boxHeight),
                cornerRadius: 4),
            with: .color(.black.opacity(0.72)))
        for (index, line) in lines.enumerated() {
            guard !line.0.isEmpty else { continue }
            let y = origin.y + 6 + Double(index) * lineHeight
            context.draw(
                Text(verbatim: line.0).font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7)),
                at: CGPoint(x: origin.x + 7, y: y), anchor: .topLeading)
            context.draw(
                Text(verbatim: line.1).font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundColor(.white),
                at: CGPoint(x: origin.x + boxWidth - 7, y: y), anchor: .topTrailing)
        }
    }

    static func draw(scene: WorldScene, into context: inout GraphicsContext) {
        let track = scene.race.track
        drawCenterline(track, into: &context)
        drawWalls(track, into: &context)
        drawCars(scene.race, into: &context)
    }

    /// The centerline as the physics knows it, colored by height: green at ground,
    /// through yellow, to red at deck height. If the road you see doesn't sit under
    /// this line, the *drawing* is wrong.
    private static func drawCenterline(_ track: Track, into context: inout GraphicsContext) {
        guard track.centerline.count > 1 else { return }
        let count = track.centerline.count
        for index in track.centerline.indices {
            let a = track.centerline[index]
            let b = track.centerline[(index + 1) % count]
            var path = Path()
            path.move(to: CGPoint(x: a.x, y: a.y))
            path.addLine(to: CGPoint(x: b.x, y: b.y))
            let height = track.height(ofSegment: index)
            context.stroke(path, with: .color(heightColor(height)), lineWidth: 3)
        }
        // A tick at every point, so sample density is visible too — a ramp that
        // climbs in two steps rather than twenty is a bug you can see here.
        for (index, point) in track.centerline.enumerated() {
            let size = 2.5
            let box = CGRect(
                x: point.x - size, y: point.y - size, width: size * 2, height: size * 2)
            let color = heightColor(track.height(ofPoint: index))
            context.fill(Path(ellipseIn: box), with: .color(color))
        }
    }

    /// Walls, labelled by height. Rails are drawn in their height color; the map
    /// boundary in gray, since it blocks everyone.
    private static func drawWalls(_ track: Track, into context: inout GraphicsContext) {
        for wall in track.walls {
            var path = Path()
            path.move(to: CGPoint(x: wall.a.x, y: wall.a.y))
            path.addLine(to: CGPoint(x: wall.b.x, y: wall.b.y))
            let color: Color = wall.kind == .boundary ? .gray : heightColor(wall.height)
            context.stroke(
                path, with: .color(color.opacity(0.9)),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
    }

    /// Per-car: its height, the surface the sim says it's on, and whether the sim
    /// considers it on the road at its own height.
    private static func drawCars(_ race: Race, into context: inout GraphicsContext) {
        let track = race.track
        for car in race.cars {
            let state = car.state
            let position = state.position
            // A ring in the car's height color, so a car "on the bridge" while
            // visually on the grass is obvious.
            let radius = CarGeometry.radius + 6
            let box = CGRect(
                x: position.x - radius, y: position.y - radius,
                width: radius * 2, height: radius * 2)
            context.stroke(
                Path(ellipseIn: box), with: .color(heightColor(state.height)), lineWidth: 2)

            let surface = track.surface(at: position, height: state.height)
            let toRoad = track.distanceToCenterline(position, height: state.height)
            let onRoad = toRoad <= track.halfWidth(atHeight: state.height)
            let lines = [
                "h \(format(state.height))",
                "\(surface)",
                // `toRoad` is `greatestFiniteMagnitude` when NO road matches the
                // car's height (mid-air over a jump's gap). `Int(_:)` TRAPS on that
                // — it crashed the app here — and note `isFinite` is NOT the guard:
                // the sentinel is finite. Compare against a real distance instead.
                onRoad
                    ? "on road"
                    : "off road \(Track.foundRoad(toRoad) ? "\(Int(toRoad))" : "—")",
                state.isAirborne ? "AIR \(state.airborneTicks)" : "",
            ].filter { !$0.isEmpty }
            // World-space text: the context is scaled, so shrink to compensate.
            // Clear of the car and its ring, with a dark plate behind so the
            // text stays readable over asphalt, grass or kerbs alike.
            var text = context
            text.translateBy(x: position.x + radius + 6, y: position.y - radius)
            text.scaleBy(x: 2.6, y: 2.6)
            let lineHeight = 8.0
            text.fill(
                Path(
                    roundedRect: CGRect(
                        x: -2, y: -2, width: 52,
                        height: Double(lines.count) * lineHeight + 4), cornerRadius: 2),
                with: .color(.black.opacity(0.55)))
            for (index, line) in lines.enumerated() {
                // `foregroundColor` rather than `foregroundStyle`: the package
                // targets iOS 16, and the latter is 17+.
                text.draw(
                    Text(verbatim: line).font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white),
                    at: CGPoint(x: 0, y: Double(index) * lineHeight), anchor: .topLeading)
            }
        }
    }

    /// Ground → deck as green → red, so height is readable at a glance.
    private static func heightColor(_ height: Double) -> Color {
        let clamped = max(0, min(1, height))
        return Color(red: clamped, green: 1 - clamped * 0.7, blue: 0.15)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
