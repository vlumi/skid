import SkidCore
import SwiftUI

/// Everything one frame of the world needs, as plain values (the Canvas
/// renderer closure is not MainActor, so it gets copies, not the session).
struct WorldScene {
    var race: Race
    var marks: MarkStore
    var gateSpans: [(a: Vec2, b: Vec2)?]
    var colors: [Color]
    /// PB-ghost cars to draw translucently (time trial), if any.
    var ghosts: [CarState] = []
}

/// Draws the whole world procedurally into a `Canvas` context — grass,
/// kerbed asphalt ribbon, start line, marks, cars. No image assets anywhere.
enum TrackRenderer {
    // The palette. Deliberately close to the classic top-down look.
    private static let grass = Color(red: 0.28, green: 0.55, blue: 0.23)
    private static let asphalt = Color(white: 0.62)
    private static let kerbRed = Color(red: 0.82, green: 0.16, blue: 0.14)
    private static let kerbWhite = Color(white: 0.95)
    private static let rubber = Color(white: 0.15)
    private static let scuff = Color(red: 0.32, green: 0.26, blue: 0.16)

    /// The car colors players pick from. Deliberately loud, classic-arcade.
    static let carPalette: [Color] = [
        .red, .yellow, .cyan, .purple,
        Color(red: 0.3, green: 0.85, blue: 0.3), .orange, .pink, .white,
    ]

    static func draw(scene: WorldScene, into context: inout GraphicsContext, size: CGSize) {
        let race = scene.race
        let marks = scene.marks
        let gateSpans = scene.gateSpans
        let colors = scene.colors
        let track = race.track
        let scale = min(size.width / track.size.x, size.height / track.size.y)
        let offset = CGSize(
            width: (size.width - track.size.x * scale) / 2,
            height: (size.height - track.size.y * scale) / 2
        )
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(grass))
        context.translateBy(x: offset.width, y: offset.height)
        context.scaleBy(x: scale, y: scale)

        func color(_ index: Int) -> Color {
            index < colors.count ? colors[index] : carPalette[index % carPalette.count]
        }

        drawRibbon(track: track, into: &context)
        drawPatches(track: track, into: &context)
        // Which players are waiting on which gate, in car colors.
        var nextByGate: [Int: [Color]] = [:]
        for (index, car) in race.cars.enumerated() where car.progress.finishedAt == nil {
            nextByGate[car.progress.nextGate, default: []].append(color(index))
        }
        drawGates(
            gateSpans: gateSpans, nextByGate: nextByGate,
            worldCenter: Vec2(track.size.x / 2, track.size.y / 2), into: &context)
        drawMarks(marks, into: &context)

        // Ghost mode: overlapping pass-through cars go translucent so
        // pileups on the racing line stay readable.
        var translucent: Set<Int> = []
        if !race.config.carContact {
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
        }
        // The PB ghost drives under the real cars, translucent and
        // colorless — present, never in the way.
        for ghost in scene.ghosts {
            draw(car: ghost, color: .white, opacity: 0.38, into: &context)
        }
        for (index, car) in race.cars.enumerated() {
            draw(
                car: car.state, color: color(index),
                opacity: translucent.contains(index) ? 0.55 : 1,
                into: &context
            )
        }
    }

    /// A player's zone chrome on a shared screen: faint colored outline plus
    /// a corner tab on the player's own edge (where their `up` points from).
    static func drawZone(_ zone: ZoneChrome, into context: inout GraphicsContext) {
        let rect = zone.rect.insetBy(dx: 3, dy: 3)
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 10),
            with: .color(zone.color.opacity(0.28)),
            lineWidth: 2
        )
        // Tab at the middle of the zone's "home" edge (opposite of up).
        let center = Vec2(rect.midX, rect.midY)
        let halfSpan = zone.up.y != 0 ? rect.height / 2 : rect.width / 2
        let edge = center - zone.up * (halfSpan - 8)
        let tab = CGRect(x: edge.x - 22, y: edge.y - 5, width: 44, height: 10)
        context.fill(
            Path(roundedRect: tab, cornerRadius: 5), with: .color(zone.color.opacity(0.6)))
    }

    private static func ribbonPath(_ track: Track) -> Path {
        var path = Path()
        guard let first = track.centerline.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in track.centerline.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        path.closeSubpath()
        return path
    }

    private static func drawRibbon(track: Track, into context: inout GraphicsContext) {
        let path = ribbonPath(track)
        // Striped kerb: a white band just wider than the asphalt, with red
        // dashes on top, then the asphalt covers all but the protruding edge.
        let kerbStyle = StrokeStyle(lineWidth: track.width + 16, lineCap: .round, lineJoin: .round)
        context.stroke(path, with: .color(kerbWhite), style: kerbStyle)
        context.stroke(
            path,
            with: .color(kerbRed),
            style: StrokeStyle(
                lineWidth: track.width + 16, lineCap: .butt, lineJoin: .round, dash: [24, 24])
        )
        context.stroke(
            path,
            with: .color(asphalt),
            style: StrokeStyle(lineWidth: track.width, lineCap: .round, lineJoin: .round)
        )
    }

    private static func drawPatches(track: Track, into context: inout GraphicsContext) {
        for patch in track.patches {
            let rect = CGRect(
                x: patch.center.x - patch.radius, y: patch.center.y - patch.radius,
                width: patch.radius * 2, height: patch.radius * 2
            )
            let color: Color
            switch patch.surface {
            case .mud: color = Color(red: 0.42, green: 0.30, blue: 0.16)
            case .water: color = Color(red: 0.23, green: 0.46, blue: 0.77).opacity(0.9)
            case .oil: color = Color(white: 0.1).opacity(0.55)
            case .asphalt, .grass: color = .clear
            }
            context.fill(Path(ellipseIn: rect), with: .color(color))
            // A darker rim so patches read against both asphalt and grass.
            context.stroke(
                Path(ellipseIn: rect.insetBy(dx: 1.5, dy: 1.5)),
                with: .color(color.opacity(0.8)),
                lineWidth: 3
            )
        }
    }

    /// Checkpoints drawn like physical gates on a real course: a faint line
    /// across the road with a **post** at each ribbon edge. Beside the
    /// posts, a dot lights up in each car's color whose NEXT gate this is —
    /// per-player guidance that stays honest with 2–4 players on screen.
    /// The last gate is the start/finish and keeps its checkers.
    private static func drawGates(
        gateSpans: [(a: Vec2, b: Vec2)?], nextByGate: [Int: [Color]], worldCenter: Vec2,
        into context: inout GraphicsContext
    ) {
        for (index, span) in gateSpans.enumerated() {
            guard let span else { continue }
            let isStartFinish = index == gateSpans.count - 1
            if isStartFinish {
                drawCheckers(span: span, into: &context)
            } else {
                var path = Path()
                path.move(to: CGPoint(x: span.a.x, y: span.a.y))
                path.addLine(to: CGPoint(x: span.b.x, y: span.b.y))
                context.stroke(
                    path,
                    with: .color(.white.opacity(0.3)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
            }
            drawPosts(
                span: span, colors: nextByGate[index] ?? [], worldCenter: worldCenter,
                into: &context)
        }
    }

    /// The two gate posts, plus one dot per waiting player in that player's
    /// color — clustered past the infield-side post (the infield always has
    /// room by track design; the outer post may sit against the wall).
    private static func drawPosts(
        span: (a: Vec2, b: Vec2), colors: [Color], worldCenter: Vec2,
        into context: inout GraphicsContext
    ) {
        for end in [span.a, span.b] {
            let post = CGRect(x: end.x - 6, y: end.y - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: post), with: .color(kerbWhite))
            context.stroke(
                Path(ellipseIn: post), with: .color(.black.opacity(0.55)), lineWidth: 2)
        }
        let infield =
            span.a.distance(to: worldCenter) <= span.b.distance(to: worldCenter)
            ? (post: span.a, other: span.b) : (post: span.b, other: span.a)
        let direction = (infield.post - infield.other).normalized
        for (slot, color) in colors.enumerated() {
            let center = infield.post + direction * (22 + Double(slot) * 22)
            let dot = CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
            context.fill(Path(ellipseIn: dot), with: .color(color))
            context.stroke(
                Path(ellipseIn: dot), with: .color(.white.opacity(0.9)), lineWidth: 2.5)
        }
    }

    private static func drawCheckers(
        span: (a: Vec2, b: Vec2), into context: inout GraphicsContext
    ) {
        let start = span
        // Two rows of checkers across the ribbon.
        let along = (start.b - start.a).normalized
        let across = along.perpendicular
        let squares = max(6, Int((start.b - start.a).length / 13))
        let side = (start.b - start.a).length / Double(squares)
        for row in 0..<2 {
            for i in 0..<squares where (i + row) % 2 == 0 {
                let corner = start.a + along * (Double(i) * side) + across * (Double(row) * side)
                var path = Path()
                let points = [
                    corner,
                    corner + along * side,
                    corner + along * side + across * side,
                    corner + across * side,
                ]
                path.move(to: CGPoint(x: points[0].x, y: points[0].y))
                for p in points.dropFirst() {
                    path.addLine(to: CGPoint(x: p.x, y: p.y))
                }
                path.closeSubpath()
                context.fill(path, with: .color(.black.opacity(0.8)))
            }
        }
    }

    private static func drawMarks(_ marks: MarkStore, into context: inout GraphicsContext) {
        // Marks arrive pre-batched into chunked paths — a few dozen stroke
        // calls total, whatever the segment count.
        let style = StrokeStyle(lineWidth: 4, lineCap: .round)
        for bucket in MarkStore.Bucket.allCases {
            guard let chunkList = marks.chunks[bucket] else { continue }
            let color: Color
            switch bucket {
            case .rubberLight: color = rubber.opacity(0.25)
            case .rubberHeavy: color = rubber.opacity(0.5)
            case .scuff: color = scuff.opacity(0.55)
            case .mudTrail: color = Color(red: 0.42, green: 0.30, blue: 0.16).opacity(0.5)
            case .wetTrail: color = Color(red: 0.35, green: 0.5, blue: 0.7).opacity(0.35)
            }
            for chunk in chunkList {
                context.stroke(chunk.path, with: .color(color), style: style)
            }
        }
    }

    /// The floating d-pad: a faint disc plus four arrows in the owning
    /// player's color, arrows lighting up with per-axis engagement (half or
    /// full step). Drawn in screen coordinates, over the world.
    static func drawDPad(_ pad: DPadOverlay, into context: inout GraphicsContext) {
        let disc = CGRect(
            x: pad.origin.x - pad.radius, y: pad.origin.y - pad.radius,
            width: pad.radius * 2, height: pad.radius * 2
        )
        context.fill(Path(ellipseIn: disc), with: .color(pad.color.opacity(0.12)))

        let arrows: [(Vec2, Double)] = [
            (pad.up, max(0, pad.input.throttle)),
            (pad.up * -1, max(0, -pad.input.throttle)),
            (pad.up.perpendicular, max(0, pad.input.steer)),
            (pad.up.perpendicular * -1, max(0, -pad.input.steer)),
        ]
        for (direction, engagement) in arrows {
            let tip = pad.origin + direction * (pad.radius + 16)
            let base = pad.origin + direction * (pad.radius - 14)
            let side = direction.perpendicular * 14
            var path = Path()
            path.move(to: CGPoint(x: tip.x, y: tip.y))
            path.addLine(to: CGPoint(x: base.x + side.x, y: base.y + side.y))
            path.addLine(to: CGPoint(x: base.x - side.x, y: base.y - side.y))
            path.closeSubpath()
            context.fill(path, with: .color(pad.color.opacity(0.35 + 0.6 * engagement)))
        }
    }

    private static func draw(
        car: CarState, color: Color, opacity: Double = 1, into context: inout GraphicsContext
    ) {
        var car2D = context
        car2D.opacity = opacity
        car2D.translateBy(x: car.position.x, y: car.position.y)
        car2D.rotate(by: Angle(radians: car.heading))

        let length = CarGeometry.length
        let width = CarGeometry.width
        // Tires first, so the body sits on top; open-wheel means they stick
        // out past the body sides.
        for offset in CarGeometry.tireOffsets {
            let tire = CGRect(x: offset.x - 4.5, y: offset.y - 3, width: 9, height: 6)
            car2D.fill(Path(roundedRect: tire, cornerRadius: 2), with: .color(rubber))
        }
        // Narrow open-wheeler body: a capsule nose-to-tail.
        let body = CGRect(x: -length / 2, y: -width / 4, width: length, height: width / 2)
        car2D.fill(Path(roundedRect: body, cornerRadius: width / 4), with: .color(color))
        // Cockpit dot behind the midpoint.
        let cockpit = CGRect(x: -4, y: -3.2, width: 6.4, height: 6.4)
        car2D.fill(Path(ellipseIn: cockpit), with: .color(.black.opacity(0.65)))
    }
}
