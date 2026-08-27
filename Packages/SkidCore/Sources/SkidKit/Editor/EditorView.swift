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
    /// **Whether the experimental building blocks are offered** — the Gap piece and
    /// the warp arrows that drop the road a level.
    ///
    /// A BUILD flag, not a setting: there is nothing here a player should have to
    /// decide, and a switch in the UI would be one more thing to explain about a
    /// feature whose problem is already that it needs explaining.
    ///
    /// **Its own condition rather than `DEBUG`**, because an ordinary debug build is
    /// what gets driven while testing everything else, and half-finished chrome in
    /// the way of that is the thing this avoids. Off unless the project was
    /// generated with `SKID_EXPERIMENTAL=1` — see docs/experimental-features.md.
    ///
    /// **The format and the sim are untouched.** Gaps and warps stay in the catalog,
    /// the share code (tag 9) and the compiler, so a track that uses them decodes,
    /// races and round-trips on any build. This hides two controls from the editor;
    /// it does not remove a feature.
    ///
    /// Callers test this with a plain `if`, so the gated views are still type-checked
    /// in a stock build and the optimiser drops the branch. The guarantee is
    /// REACHABILITY — nothing offers them — rather than absence from the binary.
    static var experimentalGaps: Bool {
        #if SKID_EXPERIMENTAL
        return true
        #else
        return false
        #endif
    }

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
        /// The level filter's jump list — a long-press on the Levels button, so a
        /// deep filter is one gesture instead of cycling the whole ring.
        case levels

        var id: String {
            switch self {
            case .hotbar(let slot): return "hotbar\(slot)"
            case .piece(let index): return "piece\(index)"
            case .levels: return "levels"
            }
        }
    }

    var radius: CurveRadius { CurveRadius(rawValue: radiusRaw) ?? .medium }

    /// The hotbar's contents, padded to the slot count so a corrupt or outgrown
    /// stored value can never crash or shrink the bar. Slots past the defaults read
    /// as empty rather than being filled with something arbitrary.
    /// **Stored ids the hotbar can no longer offer are dropped**, and the defaults
    /// fill in behind them.
    ///
    /// A stored value otherwise outlives the catalog it came from: bars assigned when
    /// the palette offered compounds still held a hairpin, which the picker cannot
    /// re-select and which sat in front of a newly-defaulted piece — so a feature
    /// added to the hotbar was invisible on every install that had ever touched it.
    /// Filtering on read needs no migration step and no version flag.
    var hotbar: [PieceID] {
        let stored = hotbarRaw.split(separator: ",").compactMap { PieceID($0) }
            .filter { EditorView.hotbarPieces(experimental: Self.experimentalGaps).contains($0) }
        // Nothing assignable left in the stored bar? Then it describes a palette that
        // no longer exists, so the defaults are a better answer than a row of blanks.
        // A bar the author deliberately emptied is indistinguishable from a stale one,
        // and re-offering the default costs a tap where hiding a feature costs the
        // feature.
        let base = stored.isEmpty ? HotbarSlot.defaults : stored
        return (0..<HotbarSlot.count(experimental: Self.experimentalGaps)).map { index in
            index < base.count ? base[index] : HotbarSlot.empty
        }
    }

    func assign(_ piece: PieceID, toSlot slot: Int) {
        var slots = hotbar
        guard slots.indices.contains(slot) else { return }
        slots[slot] = piece
        hotbarRaw = slots.map(String.init).joined(separator: ",")
    }

    /// Brief confirmation that the share code went to the clipboard.
    /// Whether the rename prompt is up, and the name being typed.
    @State var renamingTrack = false
    /// Pieces a car could not drive through, recomputed off the render path.
    @State var blockedPieces: Set<Int> = []
    /// Which storey the editor is working on, or nil for all of them.
    ///
    /// The map is a 2D projection of a stack, so a tap on three stacked pieces is
    /// ambiguous. Restricting it to one storey is the only way to reach a piece with
    /// others over it — and unlike cycling the tap, the state is visible on the
    /// button, so one tap still means one thing however you pan and zoom.
    /// Whether the whole-track transforms are expanded beside the undo pair. In place
    /// rather than a sheet: they change the map, so the map has to stay visible.
    @State var showTransforms = false
    // `-skid-levels` starts the mode on — the launch-argument family exists
    // because simctl cannot tap, and a Levels screenshot needs the mode on.
    @State var levelFilter: LevelFilter =
        LaunchFlag.consume("-skid-levels") ? .all : .off

    /// Brief warning that the clipboard didn't hold a readable share code.

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
        let layout = game.editorLayout ?? TrackLayout(pieces: [PieceCatalog.startPieceID])
        let walk = layout.walk()
        // **The map owns a rect; the chrome owns the rest.** The bars used to be laid
        // over a full-screen canvas, so the track — fitted to the whole screen — ran
        // underneath them and was partly covered by default, on the screen where it is
        // already at its smallest. Reported from device as the chrome's worst problem.
        // A VStack gives the canvas exactly the space between the bars instead.
        return ZStack {
            Retro.ground.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                mapRegion(layout: layout, walk: walk)
                paletteBar(walk: walk)
            }
        }
        .sheet(isPresented: $renamingTrack) {
            TrackPropertiesSheet(
                game: game, onPasted: { resetView() },
                close: { renamingTrack = false })
        }
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
        .statusBarHiddenIfAvailable()
    }

    /// The canvas and the chrome that is genuinely spatial (the close-loop chip,
    /// anchored at the loose end it acts on). Everything else lives in the bars.
    private func mapRegion(layout: TrackLayout, walk: WalkResult) -> some View {
        GeometryReader { geo in
            let transform = fitTransform(walk: walk, in: geo.size)
            ZStack {
                Canvas { context, _ in
                    EditorRenderer.draw(
                        walk: walk, width: Double(PieceCatalog.width),
                        // No end marker in gate mode: nothing there selects, so
                        // showing a selection would promise a tap that does nothing.
                        selectedEnd: game.editorMode == .gate ? nil : effectiveSelection(walk),
                        gateSeams: layout.gateSeams, gating: game.editorMode == .gate,
                        selectedPiece: game.editorMode == .gate ? nil : game.editorSelectedPiece,
                        decals: layout.decals, railed: layout.railed,
                        roadStyle: layout.roadStyle,
                        blockedPieces: blockedPieces, showLevels: levelFilter.showsBadges,
                        dimmedExcept: levelFilter.storeyOnly,
                        worldFrame: PieceCompiler.worldFrame(layout),
                        transform: transform, into: &context)
                }
                // **The gestures belong to the MAP, not to the whole screen.**
                //
                // They used to hang off the enclosing `ZStack`, which is built *after* the
                // bars are added — so a gesture on the container competed with the chrome
                // in front of it. Attached here, the buttons take their own taps and the map
                // takes the rest, which is the arrangement SwiftUI resolves predictably.
                //
                // `contentShape` makes the whole canvas hittable, including the grass — a
                // tap on nothing has a meaning here (clear the selection).
                //
                // Worth recording, since this was chased for a while: a report of a totally
                // unresponsive editor turned out to be a **stuck simulator**, not layering.
                // The same build was fine on another device. Do not infer a hit-testing bug
                // from one simulator without checking a second one first.
                .contentShape(Rectangle())
                .gesture(tapToSelect(walk: walk, transform: transform))
                .gesture(panZoom)
                // **No `.ignoresSafeArea()` here.** `transform` comes from
                // `geo.size`, which EXCLUDES the safe area, and taps arrive in that
                // same space — as does the map chrome. Letting the canvas expand
                // into the insets drew the road a fixed distance below where taps
                // landed. The grass behind it still fills the screen.

                // Close-it still sits ON the map, at the loose end it acts on —
                // there is nowhere else that means "join these two ends". The piece
                // actions moved OFF the map into a fixed row (see `selectionRow`),
                // because chrome over the road is what caused accidental deletes.
                if game.editorMode == .build {
                    mapActions(walk: walk, transform: transform)
                }
            }
            // The canvas does not clip itself, and the map zooms to 4× — without this
            // a zoomed road draws straight over the bars it was just moved out from
            // under.
            .clipped()
        }
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
        //
        // **The LAST match wins.** A warp has zero length, so its exit pose is
        // identical to its predecessor's — and taking the first match found the
        // ramp instead, reporting the height the road had BEFORE the drop. On device
        // the readout sat at 1 while the road descended to 0.
        let end = walk.openEnds[i]
        return walk.placed.last { $0.exits.contains(end) }?.exitHeight ?? 0
    }

    // MARK: - Bars

    /// A compact icon pill, for the view/layout tools. The label is the
    /// accessibility name — the icon carries the meaning visually, but a
    /// glyph alone tells a screen reader nothing.
    func iconButton(
        _ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Retro.font(14))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Retro.panel)
                .overlay(RetroBevel(thickness: 2))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(Text(label, bundle: .module))
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
    /// The editor's view of the shared fit: the same framing a thumbnail gets, plus this
    /// screen's zoom and pan. See `EditorRenderer.fit`.
    private func fitTransform(walk: WalkResult, in view: CGSize) -> EditorRenderer.Transform {
        EditorRenderer.fit(walk: walk, in: view, zoom: zoom, pan: pan)
    }
}
