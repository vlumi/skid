import SkidCore
import SwiftUI

/// Draws a **partial** (not-yet-closed) track layout for the editor: the
/// placed pieces as an asphalt ribbon, the start/finish line, and the loose
/// ends as tap targets (the selected one highlighted). Separate from
/// `TrackRenderer`, which assumes a closed, compiled `Track`.
enum EditorRenderer {
    private static let asphalt = Color(white: 0.62)
    private static let kerbWhite = Color(white: 0.95)
    private static let kerbRed = Color(red: 0.82, green: 0.16, blue: 0.14)

    /// Screen radius of a loose-end tap dot.
    static let endHitRadius: CGFloat = 26

    struct Transform {
        var scale: CGFloat
        var offset: CGSize
        func screen(_ p: Vec2) -> CGPoint {
            CGPoint(x: p.x * scale + offset.width, y: p.y * scale + offset.height)
        }
    }

    static func draw(
        walk: WalkResult, width: Double, selectedEnd: Int?,
        transform t: Transform, into context: inout GraphicsContext
    ) {
        let w = width * t.scale

        // Ground layer first, then the elevated deck on top of it (so a bridge
        // visibly crosses over the road beneath).
        let ground = walk.placed.filter { $0.entryLayer == 0 }
        let deck = walk.placed.filter { $0.entryLayer == 1 }
        strokeRibbon(ground, w: w, elevated: false, t: t, into: &context)
        if !deck.isEmpty {
            strokeRibbon(deck, w: w, elevated: true, t: t, into: &context)
        }

        // Ramp/jump pieces get chevrons pointing in the drive direction, so a
        // ramp reads as a slope, not plain road.
        for placed in walk.placed where placed.piece.layerDelta != 0 || placed.piece.launches {
            drawRampChevrons(placed, width: width, transform: t, into: &context)
        }

        // Start/finish line at the start piece's exit.
        if let start = walk.placed.first(where: { $0.id == PieceCatalog.startPieceID }) {
            drawStartLine(start, width: width, transform: t, into: &context)
        }

        // Loose ends: tap dots, the selected one filled/brighter.
        for (i, end) in walk.openEnds.enumerated() {
            let c = t.screen(end.position.vec2)
            let selected = i == selectedEnd
            let r: CGFloat = selected ? 13 : 9
            let dot = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            context.fill(
                Path(ellipseIn: dot),
                with: .color(selected ? .yellow : .white.opacity(0.9)))
            context.stroke(
                Path(ellipseIn: dot), with: .color(.black.opacity(0.6)), lineWidth: 2)
        }
    }

    /// Stroke a set of placed pieces as a ribbon. The elevated deck is lighter
    /// with a drop shadow so it reads as raised over the ground layer.
    private static func strokeRibbon(
        _ placed: [PlacedPiece], w: Double, elevated: Bool, t: Transform,
        into context: inout GraphicsContext
    ) {
        var path = Path()
        for p in placed {
            for k in p.piece.paths.indices {
                let pts = p.centerlineSamples(path: k).map { t.screen($0) }
                guard let first = pts.first else { continue }
                path.move(to: first)
                for pt in pts.dropFirst() { path.addLine(to: pt) }
            }
        }
        if elevated {
            var shadow = context
            shadow.translateBy(x: 5, y: 9)
            shadow.stroke(
                path, with: .color(.black.opacity(0.3)),
                style: StrokeStyle(lineWidth: w + 14, lineCap: .round, lineJoin: .round))
        }
        // Kerb band width and dash length scale WITH the world, so zooming out
        // shrinks the stripes evenly instead of leaving fixed-size blobs that
        // reflow. Clamp so they stay visible at extreme zoom.
        let band = max(2, 12 * t.scale)
        let dash = max(3, 24 * t.scale)
        context.stroke(
            path, with: .color(kerbWhite),
            style: StrokeStyle(lineWidth: w + band, lineCap: .round, lineJoin: .round))
        context.stroke(
            path, with: .color(kerbRed),
            style: StrokeStyle(
                lineWidth: w + band, lineCap: .butt, lineJoin: .round, dash: [dash, dash]))
        context.stroke(
            path, with: .color(elevated ? Color(white: 0.72) : asphalt),
            style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }

    /// Chevrons along a ramp/jump piece, pointing in the drive direction — a
    /// clear "this climbs / launches" marker versus flat road.
    private static func drawRampChevrons(
        _ placed: PlacedPiece, width: Double, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        let pts = placed.centerlineSamples()
        guard pts.count >= 2 else { return }
        let color: Color = placed.piece.launches ? .yellow : .white
        // A few chevrons spaced along the piece.
        let count = 3
        for c in 1...count {
            let frac = Double(c) / Double(count + 1)
            let idx = min(pts.count - 2, Int(frac * Double(pts.count - 1)))
            let a = pts[idx]
            let b = pts[idx + 1]
            let fwd = (b - a).normalized
            let side = fwd.perpendicular * (width * 0.32)
            let tip = t.screen(a + fwd * (width * 0.28))
            let l = t.screen(a - side)
            let r = t.screen(a + side)
            var chev = Path()
            chev.move(to: l)
            chev.addLine(to: tip)
            chev.addLine(to: r)
            context.stroke(
                chev, with: .color(color.opacity(0.85)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }

    private static func drawStartLine(
        _ start: PlacedPiece, width: Double, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        let pose = start.exits[0]
        let fwd = Vec2(angle: pose.heading.radians)
        let side = fwd.perpendicular * (width / 2)
        let a = t.screen(pose.position.vec2 - side)
        let b = t.screen(pose.position.vec2 + side)
        var line = Path()
        line.move(to: a)
        line.addLine(to: b)
        context.stroke(
            line, with: .color(.white),
            style: StrokeStyle(lineWidth: 6, dash: [7, 7]))
    }
}
