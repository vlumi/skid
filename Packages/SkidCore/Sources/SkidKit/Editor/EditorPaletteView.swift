import SkidCore
import SwiftUI

/// The palette's buttons: the primitive set, and nothing else.
extension EditorView {
    /// **Left · straight · right — the driving order.**
    ///
    /// The lay buttons read as the choice a driver faces at the loose end: turn left,
    /// go straight, turn right. Radius used to sit UNDER the corner pair ("adjacency
    /// implies scope"), but pitch — which scopes identically — sat elsewhere, so the
    /// rule it claimed to follow was broken next to it. All the next-piece settings now
    /// sit together below, each under its own name. Swiping a corner still changes
    /// radius (tight → medium → sweep).
    func mainRow(walk: WalkResult) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                pieceButton(corner(left: true, radius: radius), walk: walk, big: true)
                // The straight places the 1U short, but ICONS as the longer road:
                // a 1U ribbon is as wide as it is long and reads as a stub tile.
                pieceButton(
                    straight, icon: PieceCatalog.ID.straight, walk: walk, big: true)
                pieceButton(corner(left: false, radius: radius), walk: walk, big: true)
            }
            HStack(alignment: .top, spacing: 12) {
                settingGroup(Text("RADIUS", bundle: .module)) {
                    triStack(values: CurveRadius.allCases, current: radius, horizontal: true) {
                        radiusRaw = $0.rawValue
                    } content: { value in
                        radiusGlyph(value)
                    }
                }
                settingGroup(Text("PITCH", bundle: .module)) {
                    triStack(
                        values: [Pitch.up, .flat, .down], current: buildPitch, horizontal: true
                    ) {
                        buildPitch = $0
                    } content: { value in
                        pitchGlyph(value)
                    }
                }
                settingGroup(Text("WALL", bundle: .module)) {
                    railBuildToggle
                }
                // WARP with the settings: it also shapes the next piece (the one that
                // steps rather than slopes). Experimental, so the whole stepper goes
                // with the Gap it exists to serve.
                if EditorView.experimentalGaps {
                    settingGroup(Text("WARP", bundle: .module)) {
                        warpStepper(height: appendHeight(walk))
                    }
                }
            }
        }
    }

    /// One named group in the settings row — the label is most of the "better
    /// language": an unlabelled tri-stack of glyphs names neither itself nor its
    /// selected value.
    private func settingGroup<Content: View>(
        _ label: Text, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 4) {
            label
                .font(Retro.caption)
                .foregroundStyle(Retro.onGroundSoft)
            content()
        }
    }

    private func triStack<Value: Hashable, Content: View>(
        values: [Value], current: Value, horizontal: Bool = false,
        select: @escaping (Value) -> Void,
        @ViewBuilder content: @escaping (Value) -> Content
    ) -> some View {
        let layout =
            horizontal
            ? AnyLayout(HStackLayout(spacing: 2)) : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            ForEach(values, id: \.self) { value in
                Button {
                    select(value)
                } label: {
                    ZStack {
                        // The armed option is PRESSED-IN and lit, the same grammar as
                        // the mode toggles: a sticky's current value looks held down.
                        Rectangle()
                            .fill(value == current ? Retro.highlight : .black.opacity(0.25))
                        content(value)
                            .opacity(value == current ? 1 : 0.6)
                    }
                    .frame(width: horizontal ? 38 : 44, height: horizontal ? 28 : 32)
                    .overlay(RetroBevel(inset: value == current, thickness: 2))
                    // A transparent fill is not hit-testable, so unselected
                    // segments were tappable only on their glyph strokes —
                    // which read as "the selected one hogs the touch area".
                    // Every segment owns its full rectangle.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One radius option, as how much turning the radius buys: a full circle
    /// for tight, a half-circle (open down) for medium, a quarter arc from
    /// bottom-left to top-right for sweep.
    private func radiusGlyph(_ value: CurveRadius) -> some View {
        Path { path in
            switch value {
            case .tight:
                path.addEllipse(in: CGRect(x: 5, y: 3, width: 16, height: 16))
            case .medium:
                path.addArc(
                    center: CGPoint(x: 13, y: 16), radius: 10,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            case .sweep:
                path.addArc(
                    center: CGPoint(x: 24, y: 20), radius: 20,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            }
        }
        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .frame(width: 26, height: 22)
        .accessibilityLabel(Text(value.label, bundle: .module))
    }

    /// The glyph for one pitch option, as a tiny SIDE view of the road: a hill
    /// rising or falling, and a low bar for level ground.
    private func pitchGlyph(_ value: Pitch) -> some View {
        Path { path in
            switch value {
            case .up:
                path.move(to: CGPoint(x: 0, y: 14))
                path.addLine(to: CGPoint(x: 22, y: 14))
                path.addLine(to: CGPoint(x: 22, y: 0))
                path.closeSubpath()
            case .down:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 22, y: 14))
                path.addLine(to: CGPoint(x: 0, y: 14))
                path.closeSubpath()
            case .flat:
                path.addRect(CGRect(x: 0, y: 7, width: 22, height: 7))
            }
        }
        .fill(.white)
        .frame(width: 22, height: 14)
        .accessibilityLabel(
            Text(
                value == .up ? "Climb" : value == .down ? "Descend" : "Level",
                bundle: .module))
    }

    /// The hotbar: slots you fill yourself, for the pieces that aren't "corner or
    /// straight". Tap places; **long-press opens the picker**.
    ///
    /// The main row is a fixed vocabulary, so it needs no configuration; this row is
    /// open-ended and does. Today the ramp is the only thing to put here, and the
    /// rest sit empty — jumps, gaps, landings and decorations join as they land,
    /// which is exactly why the row stays assignable rather than becoming a button
    /// per family.
    func hotbarRow(walk: WalkResult) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(hotbar.enumerated()), id: \.offset) { slot, piece in
                pieceButton(piece, walk: walk, big: false, configures: .hotbar(slot))
            }
        }
    }

    /// One palette button. Tapping places its piece; long-pressing a hotbar slot
    /// opens the picker that changes what it holds. Greyed out when the piece can't
    /// be placed here — being refused beats a placement that breaks the track.
    @ViewBuilder
    func pieceButton(
        _ piece: PieceID, icon: PieceID? = nil, walk: WalkResult, big: Bool,
        configures target: PaletteTarget? = nil
    ) -> some View {
        let empty = piece == EditorView.HotbarSlot.empty
        let placeable = !empty && game.editorCanPlace(piece, pitch: buildPitch)
        let side: CGFloat = big ? 64 : 44
        ZStack {
            // A raised key, not a flat tile — these are the editor's primary buttons
            // and looked the least like ones. The icon keeps its dark face (the road
            // drawing needs the contrast); the bevel is what says "press me". An empty
            // hotbar slot is INSET instead: a socket awaiting a key.
            Rectangle()
                .fill(.black.opacity(placeable ? 0.35 : 0.15))
            if !empty {
                // At the HEAD the icon previews what will be DRAWN, which is the
                // author's own direction — the road runs out of the head, so the
                // heading is reversed and the pitch is taken as tapped. The stored
                // piece is the mirror of this (see `CouchGame.editorPlace`); showing
                // that instead would put a right-hand curve under a left-hand button.
                PieceIcon(
                    id: icon ?? piece, entryHeading: appendHeading(walk),
                    entryHeight: appendHeight(walk), pitch: buildPitch,
                    railed: game.editorRailNewPieces
                )
                .frame(width: side - 8, height: side - 8)
                .opacity(placeable ? 1 : 0.3)
            }
        }
        .frame(width: side, height: side)
        .overlay(RetroBevel(inset: empty, thickness: 2))
        .opacity(empty || placeable ? 1 : 0.5)
        .contentShape(Rectangle())
        .gesture(placeGesture(piece: piece, placeable: placeable, target: target))
        .accessibilityLabel(Text(EditorView.pieceLabel(piece), bundle: .module))
    }

    /// Tap places; long-press (hotbar only) opens the picker. Declared as one
    /// gesture so precedence is defined: on a plain `Button` the two competed and
    /// the long press only fired sometimes, which is how it behaved on device.
    private func placeGesture(
        piece: PieceID, placeable: Bool, target: PaletteTarget?
    ) -> some Gesture {
        let tap = TapGesture().onEnded {
            guard placeable else { return }
            game.editorPlace(piece, pitch: buildPitch)
        }
        // `exclusively(before:)` gives the long press priority when there is one to
        // give; without a target there's nothing to configure, so tap stands alone.
        return LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in if let target { configuring = target } }
            .exclusively(before: tap)
    }

    /// The picker a hotbar long-press opens. Includes **Empty**, so a slot can be
    /// cleared rather than only swapped.
    @ViewBuilder
    var configurationSheet: some View {
        switch configuring {
        case .hotbar(let slot):
            configurationBody(Text("Assign to slot", bundle: .module)) {
                let columns = [GridItem(.adaptive(minimum: 64), spacing: 10)]
                let options =
                    EditorView.hotbarPieces(experimental: EditorView.experimentalGaps)
                    + [EditorView.HotbarSlot.empty]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(options, id: \.self) { piece in
                        Button {
                            assign(piece, toSlot: slot)
                            configuring = nil
                        } label: {
                            slotOption(piece, chosen: hotbar[slot] == piece)
                        }
                    }
                }
            }
        case .piece(let index):
            configurationBody(Text("Piece markings", bundle: .module)) {
                let current = game.editorLayout?.decal(at: index)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        decalOption(nil, at: index, chosen: current == nil)
                        ForEach(Decal.allCases, id: \.self) { decal in
                            decalOption(decal, at: index, chosen: current == decal)
                        }
                    }
                }
            }
        // Railings are NOT here any more: they moved to the fixed selection row, so
        // toggling one is a single tap rather than select-open-check-close. This sheet
        // is only for the things that genuinely need a picker.
        case nil:
            EmptyView()
        }
    }

    /// One option in the slot picker.
    private func slotOption(_ piece: PieceID, chosen: Bool) -> some View {
        VStack(spacing: 4) {
            if piece == EditorView.HotbarSlot.empty {
                Image(systemName: "slash.circle")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 44, height: 44)
            } else {
                PieceIcon(id: piece)
                    .frame(width: 44, height: 44)
            }
            Text(EditorView.pieceLabel(piece), bundle: .module)
                .font(.caption2)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            chosen ? Color.white.opacity(0.18) : .black.opacity(0.25),
            in: RoundedRectangle(cornerRadius: 8))
    }

    private func configurationBody<Content: View>(
        _ title: Text, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 16) {
            title.font(.headline).foregroundColor(.white)
            content()
            Button {
                configuring = nil
            } label: {
                Text("Done", bundle: .module).pillStyle()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.18, green: 0.34, blue: 0.15).ignoresSafeArea())
    }

    /// **Delete-last and Close-it, overlaid on the map where they act.**
    ///
    /// They used to be pills in the bottom bar, which cost a whole row and put
    /// them nowhere near what they affect. Both are anchored actions — delete
    /// removes the piece at the end of the chain, close fills the gap at the loose
    /// end — so they belong at that end of the track. It also buys back the row.
    @ViewBuilder
    func mapActions(walk: WalkResult, transform: EditorRenderer.Transform) -> some View {
        if let end = looseEndPose(walk) {
            let point = transform.screen(end.position.vec2)
            // Just Close-it now: delete moved onto the SELECTED piece, where it
            // says what it will remove instead of always meaning "the last one".
            closeItAction
                // Offset clear of the end marker itself, and kept on screen.
                .position(x: point.x, y: point.y - 34)
        }
    }

    /// The loose end the actions attach to — the one a new piece would extend,
    /// which follows the build-end arrows.
    private func looseEndPose(_ walk: WalkResult) -> PiecePose? {
        if let pose = buildEndPose(walk) { return pose }
        // A closed ring has no loose end; anchor to the start piece's entry so
        // Delete is still reachable after closing the loop.
        guard let start = walk.placed.first(where: { $0.id == PieceCatalog.startPieceID })
        else { return nil }
        return PiecePose(position: start.entry.position, heading: start.entry.heading)
    }

    /// The suggester's verdict, as a compact overlay chip.
    @ViewBuilder
    private var closeItAction: some View {
        switch closingOutcome {
        case .found(let run) where !run.isEmpty && game.editorActiveEnd != nil:
            mapAction("flag.checkered", tint: .yellow, label: "Close the loop") {
                game.editorAppendRun(run)
            }
        // Same question, different answer: no run of catalog pieces reaches, but one
        // fitting piece does. Marked distinctly so it is clear the track is being
        // closed by a custom-shaped piece rather than by the ordinary vocabulary.
        //
        // Offered wherever the chip is, and it does the same thing: closing is one
        // operation. Which end the button sat on says nothing about the result —
        // either way the fitter lands last, closing onto the origin inlet (that
        // pinned exit is what keeps `Coord` exact; see `Fitter`).
        case .fits(let fitter) where game.editorActiveEnd != nil:
            mapAction("flag.checkered", tint: .teal, label: "Close with a fitted piece") {
                game.editorAppendFitter(fitter)
            }
        default:
            // Nothing when there's no run to take: the reason already shows in the
            // hint line, and a dead button on the map would just be clutter.
            EmptyView()
        }
    }

    /// A round map/chrome button: icon, tint, and an accessibility label carrying the
    /// meaning the icon cannot.
    /// The same button around an arbitrary glyph, for the one control no SF Symbol
    /// describes: railings. Every road symbol says what SHAPE the road is, which is why
    /// the pair read as "straight or curved" — see `RailGlyph`.
    func mapAction<Glyph: View>(
        label: LocalizedStringKey, enabled: Bool = true,
        action: @escaping () -> Void, glyph: () -> Glyph
    ) -> some View {
        let content = glyph()
        return Button(action: action) {
            content
                .frame(width: 34, height: 34)
                .background(Retro.panel)
                .overlay(RetroBevel(thickness: 2))
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(Text(label, bundle: .module))
    }

    func mapAction(
        _ symbol: String, tint: Color, label: LocalizedStringKey, enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Retro.ink)
                .frame(width: 34, height: 34)
                .background(tint == .yellow ? Retro.amber : Retro.panel)
                .overlay(RetroBevel(thickness: 2))
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(Text(label, bundle: .module))
        // A .disabled() button stops acting but still lets the touch through to
        // the map's tap gesture underneath, which toggles a gate seam — a real
        // edit that spends the redo tail. So while disabled, sit a gesture on top
        // that swallows the tap and does nothing.
        .overlay {
            if !enabled {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {}
            }
        }
    }
}
