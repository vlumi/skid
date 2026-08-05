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
    /// The pitch it will be laid at — so a climbing piece previews its slope.
    var pitch: Pitch = .flat
    /// Whether it will be laid WITH railings, from the palette's rails toggle.
    ///
    /// Was inferred from elevation (`climb != 0 || exitHeight > 0.5`), which stopped
    /// being true when railings became a per-piece attribute: the palette drew a
    /// blue-railed deck and laid a bare one. It has to be told.
    var railed = false

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
            exits: piece.paths.map { $0.exit(from: entry) }, entryHeight: entryHeight,
            entrySeam: 0, pitch: pitch)
        let pts = placed.piece.paths.indices.flatMap { placed.centerlineSamples(path: $0) }
        guard pts.count >= 2 else { return }
        // Shared reference scale so a tight curve reads tighter than a sweeper;
        // center the piece's bounding box in the tile. Same y-down orientation
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
        // A jump draws as lip · AIR · landing, so the button shows the hole rather
        // than a straight indistinguishable from the plain one beside it. Taken
        // from the piece's own `gapSpan`, so the icon cannot drift from the road
        // the compiler builds.
        //
        // The span is INTERPOLATED along the path rather than filtered out of the
        // samples: a straight has only its two endpoints, so neither of them falls
        // inside the gap and a sample filter would draw a solid road.
        if let gap = placed.piece.gapSpan, let ends = jumpEnds(of: placed, gap: gap) {
            path = Path()
            path.move(to: screen(ends.start))
            path.addLine(to: screen(ends.lip))
            path.move(to: screen(ends.landing))
            path.addLine(to: screen(ends.end))
        }
        // Plain road with thin light edges — no kerbs in the palette (kerbs are
        // decoration, and decoration is a later, author-controlled thing).
        //
        // **The casing shows RAILINGS, not elevation.** It used to key off
        // `climb != 0 || exitHeight > 0.5`, which was a fair proxy while every raised
        // piece was railed — and became a lie when railings turned into a per-piece
        // attribute: the button drew a blue-railed deck and laid a bare one. The rails
        // toggle drives it now, so every shape button in the palette answers "walled or
        // plain?" at a glance, which is also what makes the toggle's own state legible.
        let roadW: CGFloat = 13
        // A raised road is still drawn a shade lighter, so height stays visible on its
        // own — it just no longer masquerades as a railing.
        let raised = placed.climb != 0 || placed.exitHeight > 0.5
        context.stroke(
            path,
            with: .color(
                railed ? EditorRenderer.bridgeRail : Color(white: 0.95)),
            style: StrokeStyle(lineWidth: roadW + 4, lineCap: .butt, lineJoin: .round))
        context.stroke(
            path, with: .color(Color(white: raised ? 0.72 : 0.62)),
            style: StrokeStyle(lineWidth: roadW, lineCap: .butt, lineJoin: .round))
        drawEntryMarker(placed, screen: screen, into: &context)
    }

    /// The four points a gapped piece draws between: the run onto the lip, and the
    /// landing onward. Interpolated along the sampled path by distance, so it holds
    /// for a curved jump if one is ever added.
    private struct JumpEnds {
        var start: Vec2
        var lip: Vec2
        var landing: Vec2
        var end: Vec2
    }

    private func jumpEnds(of placed: PlacedPiece, gap: ClosedRange<Double>) -> JumpEnds? {
        let samples = placed.centerlineSamples()
        guard let start = samples.first, let end = samples.last, samples.count > 1,
            let lip = placed.point(atFraction: gap.lowerBound),
            let landing = placed.point(atFraction: gap.upperBound)
        else { return nil }
        return JumpEnds(start: start, lip: lip, landing: landing, end: end)
    }

    /// A small arrowhead at the piece's ENTRY, pointing the way traffic drives
    /// in. Without it a symmetric shape is ambiguous — a 180° hairpin's left and
    /// right variants are mirror images that look identical once the icon
    /// centers them, so there's no way to tell which way it turns.
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
