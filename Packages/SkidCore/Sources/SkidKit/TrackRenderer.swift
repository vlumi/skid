import SkidCore
import SwiftUI

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
    private static let playerColors: [Color] = [.red, .yellow, .cyan, .purple]

    static func playerColor(_ index: Int) -> Color {
        playerColors[index % playerColors.count]
    }

    static func draw(
        race: Race, marks: MarkStore, gateSpans: [(a: Vec2, b: Vec2)?],
        into context: inout GraphicsContext, size: CGSize
    ) {
        let track = race.track
        let scale = min(size.width / track.size.x, size.height / track.size.y)
        let offset = CGSize(
            width: (size.width - track.size.x * scale) / 2,
            height: (size.height - track.size.y * scale) / 2
        )
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(grass))
        context.translateBy(x: offset.width, y: offset.height)
        context.scaleBy(x: scale, y: scale)

        drawRibbon(track: track, into: &context)
        drawPatches(track: track, into: &context)
        let nextGate = race.cars.first?.progress.nextGate
        drawGateLines(gateSpans: gateSpans, nextGate: nextGate, into: &context)
        drawStartLine(
            span: gateSpans.last.flatMap { $0 },
            highlighted: nextGate == gateSpans.count - 1,
            into: &context
        )
        drawMarks(marks, into: &context)
        for (index, car) in race.cars.enumerated() {
            draw(car: car.state, color: playerColors[index % playerColors.count], into: &context)
        }
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

    /// Checkpoint lines on the road: the on-ribbon part of every gate but
    /// the last (that's the start line), translucent white with the
    /// player's NEXT gate highlighted — you can always see where to go.
    private static func drawGateLines(
        gateSpans: [(a: Vec2, b: Vec2)?], nextGate: Int?, into context: inout GraphicsContext
    ) {
        for (index, span) in gateSpans.enumerated().dropLast() {
            guard let span else { continue }
            let isNext = index == nextGate
            var path = Path()
            path.move(to: CGPoint(x: span.a.x, y: span.a.y))
            path.addLine(to: CGPoint(x: span.b.x, y: span.b.y))
            context.stroke(
                path,
                with: .color(.white.opacity(isNext ? 0.85 : 0.3)),
                style: StrokeStyle(lineWidth: isNext ? 7 : 4, lineCap: .round)
            )
        }
    }

    private static func drawStartLine(
        span: (a: Vec2, b: Vec2)?, highlighted: Bool, into context: inout GraphicsContext
    ) {
        guard let start = span else { return }
        if highlighted {
            // The start/finish is the next gate: glow under the checkers.
            var path = Path()
            path.move(to: CGPoint(x: start.a.x, y: start.a.y))
            path.addLine(to: CGPoint(x: start.b.x, y: start.b.y))
            context.stroke(
                path,
                with: .color(.white.opacity(0.6)),
                style: StrokeStyle(lineWidth: 14, lineCap: .round)
            )
        }
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

    private static func draw(car: CarState, color: Color, into context: inout GraphicsContext) {
        var car2D = context
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
