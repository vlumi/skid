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
        // Ribbon: stroke each placed piece's centerline, kerb then asphalt.
        var path = Path()
        for placed in walk.placed {
            for k in placed.piece.paths.indices {
                let pts = placed.centerlineSamples(path: k).map { t.screen($0) }
                guard let first = pts.first else { continue }
                path.move(to: first)
                for pt in pts.dropFirst() { path.addLine(to: pt) }
            }
        }
        let w = width * t.scale
        context.stroke(
            path, with: .color(kerbWhite),
            style: StrokeStyle(lineWidth: w + 12, lineCap: .round, lineJoin: .round))
        context.stroke(
            path, with: .color(kerbRed),
            style: StrokeStyle(lineWidth: w + 12, lineCap: .butt, lineJoin: .round, dash: [18, 18]))
        context.stroke(
            path, with: .color(asphalt),
            style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))

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
