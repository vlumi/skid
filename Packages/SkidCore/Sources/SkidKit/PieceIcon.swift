import SkidCore
import SwiftUI

/// A palette tile's icon: a small preview of the piece's shape (its centerline
/// stroked as a stubby road), so the palette reads by shape not text. The
/// ramp sentinel draws an up-chevron.
struct PieceIcon: View {
    let id: PieceID
    /// The heading the piece will enter at (the selected loose end) — the icon
    /// rotates to match, previewing exactly how the piece will land.
    var entryHeading: Heading = .east
    /// The height the piece will enter at — so an icon previews the elevated
    /// (deck) look when building on the bridge, matching what you'll get.
    var entryHeight: Double = 0

    var body: some View {
        Canvas { context, size in
            // Enough margin that the entry marker (which sits just outside the
            // piece, pointing in) stays inside the tile.
            let inset: CGFloat = 15
            let box = CGRect(
                x: inset, y: inset, width: size.width - 2 * inset,
                height: size.height - 2 * inset)
            if id == -1 {
                drawRampChevron(in: box, into: &context)
            } else {
                drawPieceShape(in: box, into: &context)
            }
        }
    }

    /// Walk the piece from an entry pose matching the selected loose end's
    /// heading, then fit its centerline into the box. Rotating the whole icon
    /// keeps left/right as honest mirrors (they rotate together) and previews
    /// how the piece will actually land.
    private func drawPieceShape(in box: CGRect, into context: inout GraphicsContext) {
        guard let piece = PieceCatalog.piece(id) else { return }
        let entry = PiecePose(position: .zero, heading: entryHeading)
        let placed = PlacedPiece(
            id: id, piece: piece, entry: entry,
            exits: piece.paths.map { $0.exit(from: entry) }, entryHeight: entryHeight, entrySeam: 0)
        let pts = placed.piece.paths.indices.flatMap { placed.centerlineSamples(path: $0) }
        guard pts.count >= 2 else { return }
        // Shared reference scale so a tight curve reads tighter than a sweeper;
        // centre the piece's bounding box in the tile. Same y-down orientation
        // as the canvas, so the icon matches how the piece lands.
        let reference: CGFloat = 340
        let scale = box.width / reference
        let cx = (pts.map(\.x).min()! + pts.map(\.x).max()!) / 2
        let cy = (pts.map(\.y).min()! + pts.map(\.y).max()!) / 2
        func screen(_ p: Vec2) -> CGPoint {
            CGPoint(x: box.midX + (p.x - cx) * scale, y: box.midY + (p.y - cy) * scale)
        }
        var path = Path()
        for k in placed.piece.paths.indices {
            let seg = placed.centerlineSamples(path: k).map(screen)
            guard let first = seg.first else { continue }
            path.move(to: first)
            for pt in seg.dropFirst() { path.addLine(to: pt) }
        }
        // Render like a real road tile: kerb band, red/white dashes, asphalt —
        // a mini version of what the piece draws on the canvas, so the icon
        // matches the actual piece. Elevated (ramp) uses the blue rail.
        let roadW: CGFloat = 13
        // Elevated look for ramps AND for flat pieces laid on the deck.
        let elevated = placed.piece.heightDelta != 0 || placed.exitHeight > 0.5
        if elevated {
            context.stroke(
                path, with: .color(Color(red: 0.55, green: 0.78, blue: 0.95)),
                style: StrokeStyle(lineWidth: roadW + 6, lineCap: .butt, lineJoin: .round))
            context.stroke(
                path, with: .color(Color(white: 0.72)),
                style: StrokeStyle(lineWidth: roadW, lineCap: .butt, lineJoin: .round))
        } else {
            context.stroke(
                path, with: .color(Color(white: 0.95)),
                style: StrokeStyle(lineWidth: roadW + 5, lineCap: .butt, lineJoin: .round))
            context.stroke(
                path, with: .color(Color(red: 0.82, green: 0.16, blue: 0.14)),
                style: StrokeStyle(
                    lineWidth: roadW + 5, lineCap: .butt, lineJoin: .round, dash: [5, 5]))
            context.stroke(
                path, with: .color(Color(white: 0.62)),
                style: StrokeStyle(lineWidth: roadW, lineCap: .butt, lineJoin: .round))
        }
        drawEntryMarker(placed, screen: screen, into: &context)
    }

    /// A small arrowhead at the piece's ENTRY, pointing the way traffic drives
    /// in. Without it a symmetric shape is ambiguous — a 180° hairpin's left and
    /// right variants are mirror images that look identical once the icon
    /// centres them, so there's no way to tell which way it turns.
    private func drawEntryMarker(
        _ placed: PlacedPiece, screen: (Vec2) -> CGPoint, into context: inout GraphicsContext
    ) {
        let samples = placed.centerlineSamples()
        guard samples.count >= 2 else { return }
        let start = screen(samples[0])
        let next = screen(samples[1])
        let dx = next.x - start.x
        let dy = next.y - start.y
        let length = max(0.001, (dx * dx + dy * dy).squareRoot())
        let fx = dx / length
        let fy = dy / length
        // The marker sits OUTSIDE the tile, behind the entry, pointing in at it
        // — a "traffic comes in here" cue rather than a marking painted on the
        // road (which read as part of the track).
        let size: CGFloat = 6
        let standoff = size * 2.1
        // Tip on the entry edge; the arrow body trails back away from the piece.
        let tip = CGPoint(x: start.x - fx * size * 0.5, y: start.y - fy * size * 0.5)
        let tail = CGPoint(x: start.x - fx * standoff, y: start.y - fy * standoff)
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tail.x - fy * size * 0.7, y: tail.y + fx * size * 0.7))
        head.addLine(to: CGPoint(x: tail.x + fy * size * 0.7, y: tail.y - fx * size * 0.7))
        head.closeSubpath()
        context.fill(head, with: .color(.yellow))
    }

    private func drawRampChevron(in box: CGRect, into context: inout GraphicsContext) {
        var chev = Path()
        chev.move(to: CGPoint(x: box.minX, y: box.maxY))
        chev.addLine(to: CGPoint(x: box.midX, y: box.minY))
        chev.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        context.stroke(
            chev, with: .color(.yellow),
            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        var chev2 = Path()
        let dy = box.height * 0.34
        chev2.move(to: CGPoint(x: box.minX, y: box.maxY - dy))
        chev2.addLine(to: CGPoint(x: box.midX, y: box.minY - dy + 4))
        chev2.addLine(to: CGPoint(x: box.maxX, y: box.maxY - dy))
        context.stroke(
            chev2, with: .color(.yellow.opacity(0.6)),
            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
    }
}
