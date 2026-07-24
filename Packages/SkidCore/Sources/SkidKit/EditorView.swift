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
                    HStack(spacing: 8) {
                        ForEach(palette) { item in
                            Button {
                                if item.id == PaletteItem.rampSentinel {
                                    game.editorRamp()
                                } else {
                                    game.editorAppend(item.id)
                                }
                            } label: {
                                Text(item.label, bundle: .module)
                                    .font(.callout.bold())
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(.black.opacity(0.3), in: Capsule())
                                    .foregroundStyle(.white)
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
