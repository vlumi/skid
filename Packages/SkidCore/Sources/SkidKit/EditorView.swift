import SkidCore
import SwiftUI

/// The track editor — **preview slice**: renders the current editor layout
/// (compiled to a runtime `Track`) on a pan/zoomable canvas, using the same
/// `TrackRenderer` the game draws with. Editing tools (append/select/delete,
/// gates, save, test-drive) arrive in the next slice; this establishes the
/// screen, the live compile→render path, and navigation in and out.
struct EditorView: View {
    @ObservedObject var game: CouchGame

    // View transform over the world (pan in points, zoom factor).
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    // Committed transform at the start of the current gesture.
    @State private var baseZoom: CGFloat = 1
    @State private var basePan: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let track = game.editorTrack()
            ZStack {
                Color(red: 0.28, green: 0.55, blue: 0.23).ignoresSafeArea()

                if let track {
                    canvas(track: track, size: geo.size)
                } else {
                    // Not yet saveable — the preview can't compile.
                    Text("Track not complete", bundle: .module)
                        .foregroundStyle(.white.opacity(0.7))
                }

                controls
            }
            .contentShape(Rectangle())
            .gesture(panZoom)
        }
        .statusBarHiddenIfAvailable()
    }

    /// The world drawn with the game's renderer, fit to the view then scaled /
    /// panned by the gesture transform.
    private func canvas(track: Track, size: CGSize) -> some View {
        // Frame the track's own footprint (not the whole empty canvas), so a
        // small track fills the view. mapRect maps world→screen; place it so
        // the track's bounding box is centred and contained.
        let fit = fittedRect(for: track, in: size)
        let scene = previewScene(track: track, mapRect: fit)
        return Canvas { context, canvasSize in
            var ctx = context
            ctx.translateBy(x: pan.width, y: pan.height)
            // Scale about the view centre so pinch feels centred.
            ctx.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
            ctx.scaleBy(x: zoom, y: zoom)
            ctx.translateBy(x: -canvasSize.width / 2, y: -canvasSize.height / 2)
            TrackRenderer.draw(scene: scene, into: &ctx, size: canvasSize)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var controls: some View {
        VStack {
            HStack {
                Button {
                    game.backToSetup()
                } label: {
                    Text("Done", bundle: .module).pillStyle()
                }
                Spacer()
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

    // MARK: - Gestures

    private var panZoom: some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                pan = CGSize(
                    width: basePan.width + value.translation.width,
                    height: basePan.height + value.translation.height)
            }
            .onEnded { _ in basePan = pan }
        let pinch = MagnificationGesture()
            .onChanged { scale in zoom = max(0.4, min(4, baseZoom * scale)) }
            .onEnded { _ in baseZoom = zoom }
        return SimultaneousGesture(drag, pinch)
    }

    private func resetView() {
        zoom = 1
        baseZoom = 1
        pan = .zero
        basePan = .zero
    }

    // MARK: - Preview scene

    /// A car-less `WorldScene` for rendering a track without a race running.
    private func previewScene(track: Track, mapRect: CGRect) -> WorldScene {
        let race = Race(track: track, players: [])
        let spans = track.gates.map { track.ribbonSpan(of: $0) }
        return WorldScene(
            race: race, marks: MarkStore(), gateSpans: spans, colors: [], mapRect: mapRect)
    }

    /// Frame the track's own footprint (its centerline bounding box + road
    /// width) to fill the view with a margin, preserving aspect. Returns the
    /// `mapRect` (where the full `track.size` box lands) that achieves it —
    /// `TrackRenderer.draw` scales world→screen by `mapRect.width/size.x`.
    private func fittedRect(for track: Track, in view: CGSize) -> CGRect {
        let bounds = footprint(of: track)
        let margin: CGFloat = 32
        let box = CGSize(
            width: max(1, view.width - 2 * margin), height: max(1, view.height - 2 * margin))
        let scale = min(box.width / bounds.width, box.height / bounds.height)
        // mapRect is the full size box at this scale; offset so the footprint
        // centres in the view.
        let mapW = track.size.x * scale
        let mapH = track.size.y * scale
        let footScreenX = bounds.minX * scale
        let footScreenY = bounds.minY * scale
        let originX = (view.width - bounds.width * scale) / 2 - footScreenX
        let originY = (view.height - bounds.height * scale) / 2 - footScreenY
        return CGRect(x: originX, y: originY, width: mapW, height: mapH)
    }

    /// The track's drawn footprint: centerline bounding box padded by half the
    /// road width.
    private func footprint(of track: Track) -> CGRect {
        let xs = track.centerline.map(\.x)
        let ys = track.centerline.map(\.y)
        let half = track.width / 2
        let minX = (xs.min() ?? 0) - half
        let maxX = (xs.max() ?? track.size.x) + half
        let minY = (ys.min() ?? 0) - half
        let maxY = (ys.max() ?? track.size.y) + half
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
}
