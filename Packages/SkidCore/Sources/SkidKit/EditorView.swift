import SkidCore
import SwiftUI

/// The track editor — **editing slice**: build a track piece by piece. The
/// partial layout renders live (open chains included) via `EditorRenderer`;
/// tap a loose end to select it (the last one auto-selects), then tap a
/// palette piece to extend it. Delete removes the last piece; Save is enabled
/// once the layout closes into a valid track. (Test-drive lands with step 3.)
struct EditorView: View {
    @ObservedObject var game: CouchGame

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var baseZoom: CGFloat = 1
    @State private var basePan: CGSize = .zero
    /// Index into the walk's `openEnds`; nil = none selected.
    @State private var selectedEnd: Int?

    private struct PaletteItem: Identifiable {
        let id: PieceID
        let label: LocalizedStringKey
        /// A sentinel id meaning "the context-aware ramp" (up from ground,
        /// down from the deck) — resolved to a real piece id on tap.
        static let rampSentinel = -1
    }

    /// The append palette (v1 core geometry the phone build needs first).
    /// "Ramp" is a single button: with only two elevations, it picks up from
    /// the ground and down from the deck automatically (see `game.editorRamp`).
    private let palette: [PaletteItem] = [
        .init(id: 1, label: "Straight"),
        .init(id: 7, label: "Left"),
        .init(id: 8, label: "Right"),
        .init(id: 9, label: "Left ›"),
        .init(id: 10, label: "Right ›"),
        .init(id: PaletteItem.rampSentinel, label: "Ramp"),
    ]

    var body: some View {
        GeometryReader { geo in
            let layout = game.editorLayout ?? TrackLayout(pieces: [PieceCatalog.startPieceID])
            let walk = layout.walk()
            let transform = fitTransform(walk: walk, in: geo.size)
            ZStack {
                Color(red: 0.28, green: 0.55, blue: 0.23).ignoresSafeArea()

                Canvas { context, _ in
                    EditorRenderer.draw(
                        walk: walk, width: Double(PieceCatalog.width),
                        selectedEnd: effectiveSelection(walk),
                        transform: transform, into: &context)
                }
                .ignoresSafeArea()

                topBar
                paletteBar(walk: walk)
            }
            .contentShape(Rectangle())
            .gesture(tapToSelect(walk: walk, transform: transform))
            .gesture(panZoom)
        }
        .statusBarHiddenIfAvailable()
    }

    // MARK: - Selection

    /// The selected end, defaulting to the LAST loose end (the one you just
    /// laid) so the common case needs no tap.
    private func effectiveSelection(_ walk: WalkResult) -> Int? {
        if let selectedEnd, walk.openEnds.indices.contains(selectedEnd) { return selectedEnd }
        return walk.openEnds.isEmpty ? nil : walk.openEnds.count - 1
    }

    /// The heading a newly-appended piece will enter at — the selected loose
    /// end's heading — so the palette icons render rotated to match where the
    /// piece will actually land. Defaults to east.
    private func appendHeading(_ walk: WalkResult) -> Heading {
        guard let i = effectiveSelection(walk), walk.openEnds.indices.contains(i) else {
            return .east
        }
        return walk.openEnds[i].heading
    }

    // MARK: - Bars

    private var topBar: some View {
        VStack {
            HStack {
                Button {
                    game.backToSetup()
                } label: {
                    Text("Done", bundle: .module).pillStyle()
                }
                Spacer()
                Button {
                    game.editorReset()
                } label: {
                    Text("New", bundle: .module).pillStyle()
                }
                Button {
                    resetView()
                } label: {
                    Text("Fit", bundle: .module).pillStyle()
                }
            }
            .padding()
            Spacer()
        }
    }

    private func paletteBar(walk: WalkResult) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                // Save state / validity hint.
                if game.editorIsSaveable() {
                    Text("Track complete", bundle: .module)
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("Extend the loose end to close the loop", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(palette) { item in
                            Button {
                                if item.id == PaletteItem.rampSentinel {
                                    game.editorRamp()
                                } else {
                                    game.editorAppend(item.id)
                                }
                            } label: {
                                PieceIcon(id: item.id, entryHeading: appendHeading(walk))
                                    .frame(width: 56, height: 56)
                                    .background(
                                        .black.opacity(0.3),
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .accessibilityLabel(Text(item.label, bundle: .module))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                Button(role: .destructive) {
                    game.editorDeleteLast()
                } label: {
                    Text("Delete last", bundle: .module)
                        .font(.callout.bold())
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.black.opacity(0.3), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Gestures

    private func tapToSelect(walk: WalkResult, transform: EditorRenderer.Transform) -> some Gesture
    {
        SpatialTapGesture().onEnded { value in
            // Tap a loose end to select it; tap elsewhere clears the selection
            // (falling back to auto-select-last).
            selectedEnd = walk.openEnds.firstIndex { end in
                let p = transform.screen(end.position.vec2)
                return hypot(p.x - value.location.x, p.y - value.location.y)
                    < EditorRenderer.endHitRadius
            }
        }
    }

    private var panZoom: some Gesture {
        let drag = DragGesture()
            .onChanged {
                pan = CGSize(
                    width: basePan.width + $0.translation.width,
                    height: basePan.height + $0.translation.height)
            }
            .onEnded { _ in basePan = pan }
        let pinch = MagnificationGesture()
            .onChanged { zoom = max(0.4, min(4, baseZoom * $0)) }
            .onEnded { _ in baseZoom = zoom }
        return SimultaneousGesture(drag, pinch)
    }

    private func resetView() {
        zoom = 1
        baseZoom = 1
        pan = .zero
        basePan = .zero
    }

    // MARK: - Fit

    /// Build a world→screen transform that frames the layout's footprint in the
    /// view, then applies the user's zoom/pan.
    private func fitTransform(walk: WalkResult, in view: CGSize) -> EditorRenderer.Transform {
        let pts = walk.placed.flatMap { placed in
            placed.piece.paths.indices.flatMap { placed.centerlineSamples(path: $0) }
        }
        let half = Double(PieceCatalog.width) / 2
        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        let minX = (xs.min() ?? 0) - half
        let maxX = (xs.max() ?? 100) + half
        let minY = (ys.min() ?? 0) - half
        let maxY = (ys.max() ?? 100) + half
        let w = max(1, maxX - minX)
        let h = max(1, maxY - minY)
        let margin: CGFloat = 40
        let box = CGSize(
            width: max(1, view.width - 2 * margin), height: max(1, view.height - 2 * margin))
        let baseScale = min(box.width / w, box.height / h)
        let scale = baseScale * zoom
        // Centre the footprint, then apply pan.
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let offset = CGSize(
            width: view.width / 2 - cx * scale + pan.width,
            height: view.height / 2 - cy * scale + pan.height)
        return EditorRenderer.Transform(scale: scale, offset: offset)
    }
}

/// A palette tile's icon: a small preview of the piece's shape (its centerline
/// stroked as a stubby road), so the palette reads by shape not text. The
/// ramp sentinel draws an up-chevron.
private struct PieceIcon: View {
    let id: PieceID
    /// The heading the piece will enter at (the selected loose end) — the icon
    /// rotates to match, previewing exactly how the piece will land.
    var entryHeading: Heading = .east

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 12
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
            exits: piece.paths.map { $0.exit(from: entry) }, entryHeight: 0, entrySeam: 0)
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
        let elevated = placed.piece.heightDelta != 0
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
