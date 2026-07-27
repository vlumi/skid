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

    /// The corner radius the palette builds with. Persisted — it's a setting, not
    /// transient UI state — and **changed by swiping the corner pair**.
    ///
    /// It's the only stored palette choice left. Angle isn't one (45° is the only
    /// primitive corner) and neither is straight length (the short straight is the
    /// only primitive straight); both used to be, back when the palette offered
    /// compounds.
    @AppStorage("skid.editor.curveRadius") var radiusRaw = CurveRadius.medium.rawValue

    /// The hotbar's slots, as a comma-separated id list (AppStorage can't hold an
    /// array).
    @AppStorage("skid.editor.hotbar") var hotbarRaw = HotbarSlot.defaults.map(String.init)
        .joined(separator: ",")

    /// Which hotbar slot's picker is open, if any.
    @State var configuring: PaletteTarget?
    /// Live drag offset for the corner carousel, so it follows the finger.
    @State var dragOffset: CGFloat = 0
    /// The pitch the next pieces are laid at. Session state, not persisted:
    /// every editing session starts on level ground. Sticky across placements
    /// (a climb is usually more than one piece); whether it should auto-reset
    /// is a device-feel question, deliberately left for testing.
    @State var buildPitch: Pitch = .flat

    /// Which hotbar slot's picker is open. Only the hotbar has one — the corners are
    /// a carousel, configured by swiping, and the straight has nothing to configure.
    enum PaletteTarget: Identifiable, Equatable {
        case hotbar(Int)

        var id: String {
            switch self {
            case .hotbar(let slot): return "hotbar\(slot)"
            }
        }
    }

    var radius: CurveRadius { CurveRadius(rawValue: radiusRaw) ?? .medium }

    /// The hotbar's contents, padded to the slot count so a corrupt or outgrown
    /// stored value can never crash or shrink the bar. Slots past the defaults read
    /// as empty rather than being filled with something arbitrary.
    var hotbar: [PieceID] {
        let stored = hotbarRaw.split(separator: ",").compactMap { PieceID($0) }
        return (0..<HotbarSlot.count).map { index in
            index < stored.count ? stored[index] : HotbarSlot.empty
        }
    }

    func assign(_ piece: PieceID, toSlot slot: Int) {
        var slots = hotbar
        guard slots.indices.contains(slot) else { return }
        slots[slot] = piece
        hotbarRaw = slots.map(String.init).joined(separator: ",")
    }

    /// Brief confirmation that the share code went to the clipboard.
    @State var copiedCode = false
    /// Brief warning that the clipboard didn't hold a readable share code.
    @State var pasteFailed = false

    /// The cached "Close it" search result, recomputed only when the layout or
    /// the selected end actually changes. The search costs tens of milliseconds,
    /// so it must never run from `body` — that made the editor unusable.
    @State var closingOutcome: ClosureOutcome?
    @State var closingRunKey: ClosingKey?

    /// What the cached suggestion was computed for.
    struct ClosingKey: Equatable, Hashable {
        var pieces: [PieceID]
        var end: PiecePose?
    }

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
                        selectedEnd: effectiveSelection(walk), gateSeams: layout.gateSeams,
                        transform: transform, into: &context)
                }
                .ignoresSafeArea()

                // Delete and Close sit ON the map, at the end they act on.
                mapActions(walk: walk, transform: transform)
                topBar
                paletteBar(walk: walk)
            }
            .contentShape(Rectangle())
            .gesture(tapToSelect(walk: walk, transform: transform))
            .gesture(panZoom)
            // Off the render path: the closing search costs tens of ms, so it
            // runs when the layout or selection changes, not per frame.
            .task(id: ClosingKey(pieces: layout.pieces, end: nil)) {
                refreshClosingRun(walk)
            }
            .onChangeCompat(of: selectedEnd) { _ in refreshClosingRun(walk) }
            // Long-pressing a hotbar slot opens its picker. A `sheet` rather than
            // `fullScreenCover` (that one is iOS-only, and this package also builds
            // for macOS), driven by `isPresented` rather than `item:` (iOS 17+,
            // and the package targets 16).
            .sheet(
                isPresented: .init(
                    get: { configuring != nil }, set: { if !$0 { configuring = nil } }
                )
            ) {
                configurationSheet
            }
        }
        .statusBarHiddenIfAvailable()
    }

    // MARK: - Selection

    /// The selected end, defaulting to the LAST loose end (the one you just
    /// laid) so the common case needs no tap.
    func effectiveSelection(_ walk: WalkResult) -> Int? {
        if let selectedEnd, walk.openEnds.indices.contains(selectedEnd) { return selectedEnd }
        return walk.openEnds.isEmpty ? nil : walk.openEnds.count - 1
    }

    /// The heading a newly-appended piece will enter at — the selected loose
    /// end's heading — so the palette icons render rotated to match where the
    /// piece will actually land. Defaults to east.
    func appendHeading(_ walk: WalkResult) -> Heading {
        guard let i = effectiveSelection(walk), walk.openEnds.indices.contains(i) else {
            return .east
        }
        return walk.openEnds[i].heading
    }

    /// The height a newly-appended piece will enter at — the selected loose
    /// end's exit height — so the palette icons preview the elevated look
    /// (deck gray + blue rail) when building on the deck. The walk doesn't
    /// carry heights on `openEnds`, so match the end pose back to the placed
    /// piece whose exit it is.
    func appendHeight(_ walk: WalkResult) -> Double {
        guard let i = effectiveSelection(walk), walk.openEnds.indices.contains(i) else {
            return 0
        }
        let end = walk.openEnds[i]
        for placed in walk.placed where placed.exits.contains(end) {
            return placed.exitHeight
        }
        return 0
    }

    // MARK: - Bars

    private var topBar: some View {
        VStack {
            HStack {
                // EVERY top-bar button is an icon. Text pills wrapped to
                // "Ce/nte/r" and "Co/pie/d" on a small phone, and adding more only
                // made it worse — seven words never fit one row. Icons do, and the
                // accessibility label carries the meaning.
                iconButton("checkmark", "Done") {
                    game.backToSetup()
                }
                Spacer()
                iconButton("doc.badge.plus", "New track") {
                    game.editorReset()
                }
                iconButton("arrow.up.left.and.arrow.down.right", "Fit view") {
                    resetView()
                }
                // Re-center the layout on the canvas. Closing a loop does this
                // automatically; the button is for tracks built before that, or
                // reshaped since.
                iconButton("scope", "Center on canvas") {
                    game.editorCenterOnCanvas()
                }
                // Turn the whole track 45°. Also the fix when the size limit
                // blocks a piece: a diagonal run spends its length on both axes
                // at once, so squaring it up shrinks the bounding box.
                iconButton("rotate.right", "Rotate 45°") {
                    game.editorRotate()
                }
                // Copy the share code out — how a design becomes a built-in, or
                // gets kept somewhere until there's a real track library. The icon
                // flips to a tick to confirm, since there's no text to change.
                iconButton(copiedCode ? "checkmark.circle.fill" : "doc.on.doc", "Copy code") {
                    copyCode()
                }
                // …and paste one back in to load it. Separate buttons on purpose:
                // one that did both could silently replace the track you're on.
                // A failed paste shows a warning icon rather than "Bad code".
                iconButton(
                    pasteFailed ? "exclamationmark.triangle.fill" : "doc.on.clipboard",
                    "Paste code"
                ) {
                    pasteCode()
                }
            }
            .padding()
            Spacer()
        }
    }

    /// A compact icon pill, for the view/layout tools. The label is the
    /// accessibility name — the icon carries the meaning visually, but a
    /// glyph alone tells a screen reader nothing.
    private func iconButton(
        _ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.callout.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.black.opacity(0.35), in: Capsule())
                .foregroundStyle(.white)
        }
        .accessibilityLabel(Text(label, bundle: .module))
    }

    private func paletteBar(walk: WalkResult) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                // Save state, or how far the selected end is from closing.
                if game.editorIsSaveable() {
                    Text("Track complete", bundle: .module)
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                } else if let gap = closureHint(walk) {
                    Text(verbatim: gap)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    Text("Extend the loose end to close the loop", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
                mainRow(walk: walk)
                // The hotbar returns when it has something to hold (jumps,
                // gaps, decorations); five empty slots are dead space.
                if !EditorView.hotbarPieces.isEmpty {
                    hotbarRow(walk: walk)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Gestures

    private func tapToSelect(walk: WalkResult, transform: EditorRenderer.Transform) -> some Gesture
    {
        SpatialTapGesture().onEnded { value in
            // Tap a loose end to select it.
            if let end = walk.openEnds.firstIndex(where: { end in
                let p = transform.screen(end.position.vec2)
                return hypot(p.x - value.location.x, p.y - value.location.y)
                    < EditorRenderer.endHitRadius
            }) {
                selectedEnd = end
                return
            }
            // Otherwise, tapping a seam toggles it as a checkpoint — the gates
            // are what make a lap have to be driven rather than cut.
            if let seam = seam(near: value.location, walk: walk, transform: transform) {
                game.editorToggleGate(seam: seam)
                return
            }
            // A tap on nothing clears the selection (falling back to
            // auto-select-last).
            selectedEnd = nil
        }
    }

    /// The seam nearest a tap, if it's close enough to count. A seam sits at a
    /// piece's entry port; seam 0 is the start/finish and can't be toggled.
    private func seam(
        near point: CGPoint, walk: WalkResult, transform: EditorRenderer.Transform
    ) -> Int? {
        var best: (seam: Int, distance: CGFloat)?
        for (index, placed) in walk.placed.enumerated() where index != 0 {
            let p = transform.screen(placed.entry.position.vec2)
            let distance = hypot(p.x - point.x, p.y - point.y)
            guard distance < EditorRenderer.endHitRadius else { continue }
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.seam
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

    func resetView() {
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
        // Center the footprint, then apply pan.
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let offset = CGSize(
            width: view.width / 2 - cx * scale + pan.width,
            height: view.height / 2 - cy * scale + pan.height)
        return EditorRenderer.Transform(scale: scale, offset: offset)
    }
}
