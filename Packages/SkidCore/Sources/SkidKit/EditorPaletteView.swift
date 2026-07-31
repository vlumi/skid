import SkidCore
import SwiftUI

/// The palette's buttons: the primitive set, and nothing else.
extension EditorView {
    /// **Left · right, then the straight.**
    ///
    /// Left and right sit next to each other so they read as one mirrored pair, and
    /// **swiping them changes radius** (tight → medium → sweep) — the one axis a
    /// corner still has now that 45° is the only primitive angle. The straight has
    /// no axis left to swipe, so it's a plain button.
    func mainRow(walk: WalkResult) -> some View {
        HStack(spacing: 12) {
            // Adjacency implies scope, so position is meaning here. PITCH
            // leads, set apart: it's the mode everything is laid in — trailing
            // beside the straight, it read as a straight-only setting. The
            // RADIUS picker sits against the corner pair, the one thing it
            // modifies. Both pickers are direct: three fixed options, a tap
            // beats a swipe.
            triStack(values: [Pitch.up, .flat, .down], current: buildPitch) {
                buildPitch = $0
            } content: { value in
                pitchGlyph(value)
            }
            .padding(.trailing, 8)
            // Radius UNDER the corner pair, exactly their width: the setting
            // visually belongs to the buttons it sits beneath, and the whole
            // group stands the same height as the pitch stack.
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    pieceButton(corner(left: true, radius: radius), walk: walk, big: true)
                    pieceButton(corner(left: false, radius: radius), walk: walk, big: true)
                }
                triStack(values: CurveRadius.allCases, current: radius, horizontal: true) {
                    radiusRaw = $0.rawValue
                } content: { value in
                    radiusGlyph(value)
                }
            }
            // The straight places the 1U short, but ICONS as the longer road:
            // a 1U ribbon is as wide as it is long and reads as a stub tile.
            pieceButton(straight, icon: PieceCatalog.ID.straight, walk: walk, big: true)
        }
    }

    /// A three-option picker as ONE segmented control: a single body, rounded
    /// on its outer corners only, hairline seams between the segments — so it
    /// reads as a toggle with three positions, not three unrelated buttons.
    private func triStack<Value: Hashable, Content: View>(
        values: [Value], current: Value, horizontal: Bool = false,
        select: @escaping (Value) -> Void,
        @ViewBuilder content: @escaping (Value) -> Content
    ) -> some View {
        let layout =
            horizontal
            ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 1))
        return layout {
            ForEach(values, id: \.self) { value in
                Button {
                    select(value)
                } label: {
                    ZStack {
                        Rectangle()
                            .fill(.black.opacity(value == current ? 0.5 : 0))
                        content(value)
                            .opacity(value == current ? 1 : 0.55)
                    }
                    .frame(width: horizontal ? 44 : 44, height: horizontal ? 28 : 32)
                    // A transparent fill is not hit-testable, so unselected
                    // segments were tappable only on their glyph strokes —
                    // which read as "the selected one hogs the touch area".
                    // Every segment owns its full rectangle.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(placeable ? 0.3 : 0.12))
            if !empty {
                PieceIcon(
                    id: icon ?? piece, entryHeading: appendHeading(walk),
                    entryHeight: appendHeight(walk), pitch: buildPitch
                )
                .frame(width: side - 8, height: side - 8)
                .opacity(placeable ? 1 : 0.3)
            }
        }
        .frame(width: side, height: side)
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
                let options = EditorView.hotbarPieces + [EditorView.HotbarSlot.empty]
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
                HStack(spacing: 10) {
                    decalOption(nil, at: index, chosen: current == nil)
                    ForEach(Decal.allCases, id: \.self) { decal in
                        decalOption(decal, at: index, chosen: current == decal)
                    }
                }
            }
        case nil:
            EmptyView()
        }
    }

    /// One markings option: no decal, or one of them. Applied in place — same
    /// geometry, different paint.
    private func decalOption(_ decal: Decal?, at index: Int, chosen: Bool) -> some View {
        Button {
            game.editorSetDecal(decal, at: index)
            configuring = nil
        } label: {
            VStack(spacing: 6) {
                Image(systemName: decal == nil ? "slash.circle" : "arrow.up")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(EditorView.decalTint(decal))
                Text(EditorView.decalLabel(decal), bundle: .module)
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
            .frame(width: 84, height: 68)
            .background(.black.opacity(chosen ? 0.5 : 0.22), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(chosen ? 0.8 : 0.25), lineWidth: chosen ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
        case .found(let run) where !run.isEmpty:
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
        case .fits(let fitter):
            mapAction("flag.checkered", tint: .teal, label: "Close with a fitted piece") {
                game.editorAppendFitter(fitter)
            }
        default:
            // Nothing when there's no run to take: the reason already shows in the
            // hint line, and a dead button on the map would just be clutter.
            EmptyView()
        }
    }

    /// **Whole-track transforms: turn either way, raise, lower.**
    ///
    /// These act on the track as a whole, so they don't belong among the top
    /// bar's file actions (Done / New / Copy / Paste) — and that row is already
    /// tight on a small phone. One row of four, laid out above the hint line
    /// rather than floated over the map: a 2×2 pad anchored to a map corner sat
    /// right on top of the palette on an SE, and a second row of buttons costs
    /// the vertical space that screen is short of.
    ///
    /// Raise/lower gray out when the shift would push any part of the track out
    /// of the world's storeys — most of the time, once a track climbs a full
    /// level.
    @ViewBuilder
    var transformPad: some View {
        HStack(spacing: 6) {
            // +eighths is counterclockwise in the ring but CLOCKWISE on screen:
            // the canvas is y-down and `screen()` doesn't flip. Hence the signs.
            mapAction("rotate.left", tint: .white, label: "Rotate 45° left") {
                game.editorRotate(eighths: -1)
            }
            mapAction("rotate.right", tint: .white, label: "Rotate 45° right") {
                game.editorRotate(eighths: 1)
            }
            mapAction(
                "arrow.up.to.line", tint: .white, label: "Raise track",
                enabled: game.canShiftHeight(steps: 1)
            ) {
                game.editorShiftHeight(steps: 1)
            }
            mapAction(
                "arrow.down.to.line", tint: .white, label: "Lower track",
                enabled: game.canShiftHeight(steps: -1)
            ) {
                game.editorShiftHeight(steps: -1)
            }
            // Undo/redo sit with the other whole-track actions because that is
            // what they are — every edit is undoable, not just piece placement.
            mapAction(
                "arrow.uturn.backward", tint: .white, label: "Undo",
                enabled: game.editorCanUndo
            ) {
                game.editorUndo()
            }
            mapAction(
                "arrow.uturn.forward", tint: .white, label: "Redo",
                enabled: game.editorCanRedo
            ) {
                game.editorRedo()
            }
        }
    }

    func mapAction(
        _ symbol: String, tint: Color, label: LocalizedStringKey, enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(tint == .yellow ? .black : .white)
                .frame(width: 34, height: 34)
                .background(
                    tint == .yellow ? Color.yellow.opacity(0.9) : .black.opacity(0.55),
                    in: Circle()
                )
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Circle())
        }
        .disabled(!enabled)
        .accessibilityLabel(Text(label, bundle: .module))
        // A .disabled() button stops acting but still lets the touch through to
        // the map's tap gesture underneath, which toggles a gate seam — a real
        // edit that spends the redo tail. So while disabled, sit a gesture on top
        // that swallows the tap and does nothing.
        .overlay {
            if !enabled {
                Circle()
                    .fill(.clear)
                    .contentShape(Circle())
                    .onTapGesture {}
            }
        }
    }
}
