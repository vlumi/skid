import SkidCore
import SwiftUI

/// The track editor: build a track piece by piece, with the partial layout
/// rendered live (open chains included) via `EditorRenderer`.
///
/// Tap a palette piece to extend the track; tap a laid piece to SELECT it, which
/// is what delete acts on and where the build-end arrows hang. Gating is its own
/// mode (`EditorGateMode`). Save is enabled once the layout closes into a valid
/// track.
struct EditorView: View {
    @ObservedObject var game: CouchGame

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var baseZoom: CGFloat = 1
    @State private var basePan: CGSize = .zero
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
    /// The pitch the next pieces are laid at. Session state, not persisted:
    /// every editing session starts on level ground. Sticky across placements
    /// (a climb is usually more than one piece); whether it should auto-reset
    /// is a device-feel question, deliberately left for testing.
    @State var buildPitch: Pitch = .flat

    /// Which hotbar slot's picker is open. Only the hotbar has one — the corners are
    /// a carousel, configured by swiping, and the straight has nothing to configure.
    enum PaletteTarget: Identifiable, Equatable {
        case hotbar(Int)
        /// A LAID piece's variants — decals, and the start line's facing. Applied
        /// in place: same geometry, different markings.
        case piece(Int)

        var id: String {
            switch self {
            case .hotbar(let slot): return "hotbar\(slot)"
            case .piece(let index): return "piece\(index)"
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
    /// Pieces a car could not drive through, recomputed off the render path.
    @State var blockedPieces: Set<Int> = []
    /// Which storey the editor is working on, or nil for all of them.
    ///
    /// The map is a 2D projection of a stack, so a tap on three stacked pieces is
    /// ambiguous. Restricting it to one storey is the only way to reach a piece with
    /// others over it — and unlike cycling the tap, the state is visible on the
    /// button, so one tap still means one thing however you pan and zoom.
    @State var levelFilter: LevelFilter = .off

    /// `off` shows no badges and selects anything; `all` badges everything; a storey
    /// badges everything and selects only that one.
    enum LevelFilter: Equatable {
        case off
        case all
        case storey(Int)

        var showsBadges: Bool { self != .off }
        var storeyOnly: Int? {
            if case .storey(let level) = self { return level }
            return nil
        }
    }
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
                        // No end marker in gate mode: nothing there selects, so
                        // showing a selection would promise a tap that does nothing.
                        selectedEnd: game.editorMode == .gate ? nil : effectiveSelection(walk),
                        gateSeams: layout.gateSeams, gating: game.editorMode == .gate,
                        selectedPiece: game.editorMode == .gate ? nil : game.editorSelectedPiece,
                        decals: layout.decals, railed: layout.railed,
                        blockedPieces: blockedPieces, showLevels: levelFilter.showsBadges,
                        dimmedExcept: levelFilter.storeyOnly,
                        transform: transform, into: &context)
                }
                // **No `.ignoresSafeArea()` here.** `transform` comes from
                // `geo.size`, which EXCLUDES the safe area, and taps arrive in that
                // same space — as does the map chrome. Letting the canvas expand
                // into the insets drew the road a fixed distance below where taps
                // landed. The grass behind it still fills the screen.

                // Close-it sits ON the map at the loose end; delete and the build
                // arrows sit on the SELECTED piece. Both are build actions, so
                // they're gone while gating.
                if game.editorMode == .build {
                    mapActions(walk: walk, transform: transform)
                    selectionChrome(walk: walk, transform: transform)
                }
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
            .onChangeCompat(of: game.editorBuildEnd) { _ in refreshClosingRun(walk) }
            // Same reasoning: the blockage check compiles the track.
            .task(id: layout.pieces) { blockedPieces = layout.blockedPieces() }
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

    /// Which loose end the palette is building at, indexing the list the renderer
    /// marks up: `walk.openEnds`, then the HEAD stub appended after them.
    ///
    /// Only the tail lives in `openEnds` — the origin is an inlet the walk can
    /// close onto, not a loose end — so the head's index is `openEnds.count`, which
    /// is exactly where `EditorRenderer.draw` appends it. Keeping both in step is
    /// what makes the construction marker follow the arrows.
    func effectiveSelection(_ walk: WalkResult) -> Int? {
        guard !walk.openEnds.isEmpty else { return nil }
        switch game.editorActiveEnd {
        case .head: return walk.openEnds.count  // the appended head stub
        case .tail: return walk.openEnds.count - 1
        case nil: return nil  // nothing selected: no end is live to mark
        }
    }

    /// The pose of the end being built at, head or tail — where the chrome that
    /// belongs to "the growing end" is anchored.
    func buildEndPose(_ walk: WalkResult) -> PiecePose? {
        guard !walk.openEnds.isEmpty else { return nil }
        switch game.editorActiveEnd {
        case .tail: return walk.openEnds.last
        case .head:
            guard let first = walk.placed.first else { return nil }
            return PiecePose(
                position: first.entry.position, heading: first.entry.heading.reversed)
        case nil: return nil
        }
    }

    /// The heading the next piece will enter at, so the palette icons render
    /// rotated to match where the piece will actually land.
    ///
    /// At the HEAD the piece leads *into* the origin, and the exact entry depends on
    /// the piece's own turn — but the origin heading is what a straight would use
    /// and is the right read for the icons.
    func appendHeading(_ walk: WalkResult) -> Heading {
        if game.editorActiveEnd == .head, let layout = game.editorLayout {
            // REVERSED: the origin heading points into piece 0 (the driving
            // direction), but the author is building the other way, and the icons
            // preview what they will DRAW. Same reason the construction marker at
            // the head faces out of the track.
            return layout.origin.heading.reversed
        }
        guard let i = effectiveSelection(walk), walk.openEnds.indices.contains(i) else {
            return .east
        }
        return walk.openEnds[i].heading
    }

    /// The height the next piece will enter at, so the palette icons preview the
    /// elevated look (deck gray + blue rail) when building on the deck.
    func appendHeight(_ walk: WalkResult) -> Double {
        if game.editorActiveEnd == .head {
            return game.editorLayout?.originHeight ?? 0
        }
        guard let i = effectiveSelection(walk), walk.openEnds.indices.contains(i) else {
            return 0
        }
        // The walk doesn't carry heights on `openEnds`, so match the end pose back
        // to the placed piece whose exit it is.
        let end = walk.openEnds[i]
        for placed in walk.placed where placed.exits.contains(end) {
            return placed.exitHeight
        }
        return 0
    }

    // MARK: - Bars

    /// A compact icon pill, for the view/layout tools. The label is the
    /// Who signed the track that was pasted in. Absent for an unsigned one,
    /// which is the norm — every built-in is unsigned, and saying so on each
    /// would be noise. A signature that does not verify DOES show: it is the
    /// only sign that a track was edited after signing.
    ///
    /// No name and no fingerprint yet; that arrives with profiles in v0.9.
    @ViewBuilder
    var attributionChip: some View {
        let attribution = game.pastedAttribution
        if attribution.isWorthShowing {
            let broken = attribution == .broken
            Image(systemName: broken ? "seal.slash" : "seal")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(broken ? .orange : .white.opacity(0.85))
                .accessibilityLabel(Text(attributionLabel(attribution), bundle: .module))
        }
    }

    private func attributionLabel(_ attribution: TrackAttribution) -> LocalizedStringKey {
        switch attribution {
        case .mine: return "Signed by you"
        case .other: return "Signed"
        case .broken: return "Signature doesn't match"
        case .unsigned: return "Not signed"
        }
    }

    /// accessibility name — the icon carries the meaning visually, but a
    /// glyph alone tells a screen reader nothing.
    func iconButton(
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

    @ViewBuilder
    func buildStatus(walk: WalkResult) -> some View {
        // Save state, or how far the selected end is from closing.
        Group {
            if game.editorIsSaveable() {
                Text("Track complete", bundle: .module)
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
            } else if let gap = closureHint(walk) {
                Text(verbatim: gap)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text("Extend the loose end to close the loop", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        // A backdrop, because the canvas-bounds dashes run right where
        // this line sits and made it hard to read.
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.black.opacity(0.35), in: Capsule())
    }

    // MARK: - Gestures

    private func tapToSelect(walk: WalkResult, transform: EditorRenderer.Transform) -> some Gesture
    {
        SpatialTapGesture().onEnded { value in
            // One tap, one meaning — decided by the mode, not by what happens to
            // be near the finger. In GATE mode seams toggle and nothing selects;
            // in BUILD mode ends select and seams are inert.
            if game.editorMode == .gate {
                if let seam = seam(near: value.location, walk: walk, transform: transform) {
                    game.editorToggleGate(seam: seam)
                }
                return
            }
            // Tap a piece to select it: that selection is what delete acts on and
            // what the build-end arrows hang off.
            if let index = piece(
                near: value.location, walk: walk, transform: transform,
                onlyLevel: levelFilter.storeyOnly)
            {
                game.editorSelect(index)
                return
            }
            // A tap on nothing clears the selection.
            game.editorSelect(nil)
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
