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

    /// Which palette tab is showing, and (in Curves) which radius the row is
    /// tuned to. Tabs exist from the start because the catalog only grows:
    /// decal variants and, later, decorations group naturally into their own
    /// tabs rather than lengthening one scroll. (The exact grouping is expected
    /// to be revisited as those families land.)
    @State var tab: PaletteTab = .curves
    @State var radius: CurveRadius = .medium

    /// The cached "Close it" suggestion, recomputed only when the layout or the
    /// selected end actually changes. The search costs tens of milliseconds, so
    /// it must never run from `body` — that made the editor unusable.
    @State private var closingRun: [PieceID]?
    @State private var closingRunKey: ClosingKey?

    /// What the cached suggestion was computed for.
    private struct ClosingKey: Equatable, Hashable {
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
            // Off the render path: the closing search costs tens of ms, so it
            // runs when the layout or selection changes, not per frame.
            .task(id: ClosingKey(pieces: layout.pieces, end: nil)) {
                refreshClosingRun(walk)
            }
            .onChangeCompat(of: selectedEnd) { _ in refreshClosingRun(walk) }
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
    /// (deck grey + blue rail) when building on the deck. The walk doesn't
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
                tabRow
                if tab == .curves { radiusRow }
                pieceRow(walk: walk)
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        game.editorDeleteLast()
                    } label: {
                        Text("Delete last", bundle: .module)
                            .font(.callout.bold())
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.black.opacity(0.3), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    // When a short run of pieces would close the loop exactly,
                    // offer it — the author doesn't have to work out what
                    // cancels a diagonal, they can just take the suggestion.
                    if let run = closingRun {
                        Button {
                            for id in run { game.editorAppend(id) }
                        } label: {
                            Text("Close it (\(run.count))", bundle: .module)
                                .font(.callout.bold())
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color.yellow.opacity(0.85), in: Capsule())
                                .foregroundStyle(.black)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    /// How far the selected loose end is from closing, in the unit system — so
    /// a stuck author can see *what kind* of gap they have. An axis-only gap is
    /// fixable with straights; a gap carrying a √2 part never is, and needs
    /// diagonal travel (a mirrored chicane, a 45° dogleg) to cancel.
    /// Returns nil when there's nothing specific to report (fall back to the
    /// generic, localized hint).
    private func closureHint(_ walk: WalkResult) -> String? {
        let layout = game.editorLayout ?? TrackLayout(pieces: [PieceCatalog.startPieceID])
        guard let i = effectiveSelection(walk), walk.openEnds.indices.contains(i) else {
            return closedLoopHint(layout)
        }
        let gap = layout.closureGap(from: walk.openEnds[i])
        var parts: [String] = []
        // Axis offsets, named by compass direction (screen y grows downward).
        if gap.axisX != 0 {
            parts.append("\(unitText(abs(gap.axisX))) \(gap.axisX > 0 ? "E" : "W")")
        }
        if gap.axisY != 0 {
            parts.append("\(unitText(abs(gap.axisY))) \(gap.axisY > 0 ? "S" : "N")")
        }
        if gap.needsDiagonalTravel {
            parts.append("\(unitText(max(abs(gap.diagonalX), abs(gap.diagonalY)))) diagonal")
        }
        let advice: String
        switch gap.remedy(facing: walk.openEnds[i].heading) {
        case .closed: return nil
        case .turn(let eighths):
            // Report the shorter way round, so 7 eighths reads as "45° left".
            let left = eighths <= 4
            advice = "turn \((left ? eighths : 8 - eighths) * 45)° \(left ? "left" : "right")"
        case .straights:
            advice = "straights will close it"
        case .tooLong:
            advice = "overshot — shorten a run instead"
        case .balanceDiagonals:
            advice = "45s must cancel — pair them opposite, or 8 round the loop"
        }
        guard !parts.isEmpty else { return "Not closed — \(advice)" }
        return "Gap \(parts.joined(separator: " + ")) — \(advice)"
    }

    /// The ring has no loose end, so anything still unsaveable is a rule other
    /// than geometry — name it, instead of telling the author to extend an end
    /// that isn't there.
    private func closedLoopHint(_ layout: TrackLayout) -> String? {
        let problems = TrackValidator.validate(layout).problems
        if problems.contains(.gates) { return "Loop closed — mark a checkpoint to finish" }
        if problems.contains(.overlap) { return "Loop closed, but it crosses itself" }
        if problems.contains(.offCanvas) { return "Loop closed, but it runs off the canvas" }
        return nil
    }

    /// Recompute the "Close it" suggestion if the layout or selection changed.
    /// Called from a task, never from `body`: the search is far too slow to run
    /// per frame (it made the editor jam).
    private func refreshClosingRun(_ walk: WalkResult) {
        let end = effectiveSelection(walk).flatMap { i in
            walk.openEnds.indices.contains(i) ? walk.openEnds[i] : nil
        }
        let key = ClosingKey(pieces: game.editorLayout?.pieces ?? [], end: end)
        guard key != closingRunKey else { return }
        closingRunKey = key
        guard let layout = game.editorLayout, let end else {
            closingRun = nil
            return
        }
        let run = layout.closingRun(from: end, maxPieces: 3)
        closingRun = (run?.isEmpty ?? true) ? nil : run
    }

    /// A unit count, trimmed to look like "2U" / "1.5U".
    private func unitText(_ units: Double) -> String {
        units == units.rounded()
            ? "\(Int(units))U" : String(format: "%.1fU", units)
    }

    /// Which family of pieces the row below shows.
    private var tabRow: some View {
        HStack(spacing: 8) {
            ForEach(PaletteTab.allCases) { item in
                chip(item.label, selected: tab == item) { tab = item }
            }
        }
    }

    /// Which radius the Curves row is tuned to — the second tier, so one row of
    /// shapes covers all three radii instead of tripling the row.
    private var radiusRow: some View {
        HStack(spacing: 8) {
            ForEach(CurveRadius.allCases) { item in
                chip(item.label, selected: radius == item, small: true) { radius = item }
            }
        }
    }

    /// A pill toggle shared by both selector rows.
    private func chip(
        _ label: LocalizedStringKey, selected: Bool, small: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label, bundle: .module)
                .font(small ? .caption.bold() : .footnote.bold())
                .padding(.horizontal, small ? 10 : 13)
                .padding(.vertical, small ? 5 : 7)
                .background(
                    selected ? Color.white.opacity(0.9) : .black.opacity(0.3), in: Capsule()
                )
                .foregroundStyle(selected ? .black : .white)
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
