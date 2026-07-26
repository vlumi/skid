import SkidCore
import SwiftUI

/// The palette's buttons: three for the common move, five assignable for
/// one-offs.
///
/// **Tap places, long-press configures** — one gesture rule for every button
/// here, which is why there are no selector chips in the resting state. The three
/// main buttons share one configuration (the corner's angle and radius, the
/// straight's length), so left and right always mirror each other; a hotbar slot
/// configures to any single one-off piece.
/// A carousel's geometry: one row tall, plus a sliver of the neighbours above and
/// below. That sliver is what says "drag me".
struct CarouselMetrics {
    var rowHeight: CGFloat = 64
    var peek: CGFloat = 9
    var spacing: CGFloat = 6
}

extension EditorView {
    /// **45L · 90L · 90R · 45R, then the straight.**
    ///
    /// Angle is a *position*, not a mode: the four corner buttons mirror around the
    /// centre, so both angles are always one tap away and there's no toggle to
    /// remember or to pay screen for. Their adjacency is also what makes left and
    /// right read as one pair.
    ///
    /// **Swipe the corner group to change radius** (tight → medium → sweep), and
    /// swipe the straight to change its length. One axis per carousel, which is why
    /// this replaced long-press-to-configure: a swipe is discoverable and fires
    /// reliably, where long-press on these did neither.
    func mainRow(walk: WalkResult) -> some View {
        HStack(spacing: 12) {
            carousel(
                values: CurveRadius.allCases, current: radius,
                select: { radiusRaw = $0.rawValue }
            ) { value in
                HStack(spacing: 6) {
                    cornerTile(left: true, angle: .degrees45, radius: value, walk: walk)
                    cornerTile(left: true, angle: .degrees90, radius: value, walk: walk)
                    cornerTile(left: false, angle: .degrees90, radius: value, walk: walk)
                    cornerTile(left: false, angle: .degrees45, radius: value, walk: walk)
                }
            }
            carousel(
                values: StraightLength.allCases, current: straightLength,
                select: { straightRaw = $0.rawValue }
            ) { value in
                pieceButton(value.piece, walk: walk, big: true)
            }
        }
    }

    /// A corner tile at an explicit radius, so a carousel row can show the
    /// neighbouring radii rather than only the selected one.
    private func cornerTile(
        left: Bool, angle: CurveAngle, radius: CurveRadius, walk: WalkResult
    ) -> some View {
        pieceButton(corner(left: left, angle: angle, radius: radius), walk: walk, big: true)
    }

    /// A **vertical** carousel that tracks your finger: the neighbouring values sit
    /// just above and below, peeking out of a clipped window, and the whole strip
    /// follows the drag before settling on the nearest one.
    ///
    /// Both details came from device feedback. The first version acted only on
    /// `onEnded`, so nothing moved under your finger and there was no way to tell a
    /// swipe had registered — it read as unreliable even when it worked. And
    /// vertical beats horizontal here because these buttons sit in a horizontal row:
    /// a sideways drag competes with the row, an up/down one doesn't. Seeing the
    /// values move is also what makes the gesture discoverable, so the value names
    /// are gone — the icons say it better.
    private func carousel<Value: Hashable, Content: View>(
        values: [Value], current: Value, metrics: CarouselMetrics = .init(),
        select: @escaping (Value) -> Void,
        @ViewBuilder content: @escaping (Value) -> Content
    ) -> some View {
        let (height, peek) = (metrics.rowHeight, metrics.peek)
        let index = values.firstIndex(of: current) ?? 0
        let step = height + metrics.spacing
        // The window is a row PLUS a sliver of the neighbours above and below —
        // that peek is what says "there's more here, drag me". A window exactly one
        // row tall clips them away entirely and the carousel looks like a plain
        // button again.
        let window = height + peek * 2
        // A window one row tall, with the strip pinned to its TOP and slid upward
        // by the selected index. Ordering matters: `.frame` after `.offset` would
        // re-centre the offset content and show the wrong row.
        return VStack(spacing: metrics.spacing) {
            ForEach(values, id: \.self) { value in
                content(value)
                    // Neighbours are dimmed and shrunk, so the live one is obvious
                    // and the others read as "there's more this way".
                    .opacity(value == current ? 1 : 0.35)
                    .scaleEffect(value == current ? 1 : 0.86)
            }
        }
        .frame(width: nil, alignment: .top)
        .offset(y: -CGFloat(index) * step + dragOffset + peek)
        .frame(height: window, alignment: .top)
        .clipped()
        // A backing plate so the clipped neighbours read against something: dimmed
        // dark tiles on dark grass were invisible, which defeated the peek.
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: index)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    // Follow the finger, but resist past the ends so the strip
                    // can't be dragged off into nothing.
                    let raw = value.translation.height
                    let atTop = index == 0 && raw > 0
                    let atEnd = index == values.count - 1 && raw < 0
                    dragOffset = (atTop || atEnd) ? raw * 0.25 : raw
                }
                .onEnded { value in
                    // Settle on whichever value the drag landed nearest.
                    let moved = Int((-value.translation.height / step).rounded())
                    let target = min(max(index + moved, 0), values.count - 1)
                    dragOffset = 0
                    if values[target] != current { select(values[target]) }
                }
        )
    }

    private func cycleRadius(by step: Int) {
        let all = CurveRadius.allCases
        guard let index = all.firstIndex(of: radius) else { return }
        radiusRaw = all[(index + step + all.count) % all.count].rawValue
    }

    private func cycleStraight(by step: Int) {
        let all = StraightLength.allCases
        guard let index = all.firstIndex(of: straightLength) else { return }
        straightRaw = all[(index + step + all.count) % all.count].rawValue
    }

    /// The hotbar: five slots you assign yourself, for the pieces that aren't part
    /// of "corner or straight". Tap places; **long-press opens the picker** — the
    /// one place that gesture remains, since assigning from a catalog of one-offs
    /// has no natural carousel axis.
    func hotbarRow(walk: WalkResult) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(hotbar.enumerated()), id: \.offset) { slot, piece in
                pieceButton(
                    tracking(piece), walk: walk, big: false, configures: .hotbar(slot))
            }
        }
    }

    /// One palette button. Tapping places its piece; long-pressing opens the sheet
    /// that changes what it places. Greyed out when the piece can't be placed here
    /// — being refused with a reason beats a placement that breaks the track.
    @ViewBuilder
    func pieceButton(
        _ piece: PieceID, walk: WalkResult, big: Bool, configures target: PaletteTarget? = nil
    ) -> some View {
        let ramp = piece == HotbarSlot.rampSentinel
        let resolved = ramp ? game.editorRampPiece() : piece
        let placeable = resolved.map { game.editorCanAppend($0) } ?? false
        let side: CGFloat = big ? 64 : 44
        // NOT a Button. A Button consumes the press for its own tap handling, so a
        // `.onLongPressGesture` attached alongside it only fires sometimes — which
        // is exactly how it behaved on device. And `.disabled` would have killed the
        // long press outright, leaving an unplaceable button impossible to
        // reconfigure. So: a plain view, with the tap and the long press declared
        // together as an explicit gesture so their precedence is defined rather
        // than emergent.
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(placeable ? 0.3 : 0.12))
            if let resolved {
                PieceIcon(
                    id: resolved, entryHeading: appendHeading(walk),
                    entryHeight: appendHeight(walk)
                )
                .frame(width: side - 8, height: side - 8)
                .opacity(placeable ? 1 : 0.3)
            }
            // Only the hotbar is long-pressable, so only it advertises it.
            if target != nil {
                Image(systemName: "ellipsis")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: side, height: side, alignment: .bottomTrailing)
                    .padding(.trailing, 3)
                    .padding(.bottom, 1)
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .gesture(placeGesture(piece: piece, ramp: ramp, placeable: placeable, target: target))
        .accessibilityLabel(Text(EditorView.pieceLabel(piece), bundle: .module))
    }

    /// A hotbar piece, **following the corner radius** where its family has a
    /// variant at that radius.
    ///
    /// So a slot holding a hairpin gives you the tight hairpin while you're building
    /// tight corners, without reassigning it — the slot means "hairpin", not
    /// "hairpin, medium". Where the family has no variant at the current radius
    /// (there's no sweep hairpin) the slot keeps what it was given rather than going
    /// blank. Jogs and the ramp never track: a jog's 240/360 is a lateral shift, not
    /// a radius, and both use a tight first arc.
    private func tracking(_ piece: PieceID) -> PieceID {
        guard let match = EditorView.family(of: piece),
            let tracked = match.family.piece(left: match.left, radius: radius)
        else { return piece }
        return tracked
    }

    /// Tap places; long-press (hotbar only) opens the picker. Declared as one
    /// gesture so precedence is defined: on a plain `Button` the two competed and
    /// the long press only fired sometimes, which is how it behaved on device.
    private func placeGesture(
        piece: PieceID, ramp: Bool, placeable: Bool, target: PaletteTarget?
    ) -> some Gesture {
        let tap = TapGesture().onEnded {
            guard placeable else { return }
            if ramp {
                game.editorRamp()
            } else {
                game.editorAppend(piece)
            }
        }
        // `exclusively(before:)` gives the long press priority when there is one to
        // give; without a target there's nothing to configure, so tap stands alone.
        return LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in if let target { configuring = target } }
            .exclusively(before: tap)
    }

    /// The picker a hotbar long-press opens.
    @ViewBuilder
    var configurationSheet: some View {
        switch configuring {
        case .hotbar(let slot):
            configurationBody(Text("Assign to slot", bundle: .module)) {
                let columns = [GridItem(.adaptive(minimum: 64), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(EditorView.oneOffPieces, id: \.self) { piece in
                        Button {
                            assign(piece, toSlot: slot)
                            configuring = nil
                        } label: {
                            VStack(spacing: 4) {
                                PieceIcon(
                                    id: piece == HotbarSlot.rampSentinel
                                        ? PieceCatalog.ID.rampUp : piece
                                )
                                .frame(width: 44, height: 44)
                                Text(EditorView.pieceLabel(piece), bundle: .module)
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                hotbar[slot] == piece
                                    ? Color.white.opacity(0.18) : .black.opacity(0.25),
                                in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        case nil:
            EmptyView()
        }
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
            HStack(spacing: 8) {
                // Delete the last piece: the chain's growing end is right here.
                if walk.placed.count > 1 {
                    mapAction("arrow.uturn.backward", tint: .white, label: "Delete last piece") {
                        game.editorDeleteLast()
                    }
                }
                closeItAction
            }
            // Offset clear of the end marker itself, and kept on screen.
            .position(x: point.x, y: point.y - 34)
        }
    }

    /// The loose end the actions attach to — the one a new piece would extend.
    private func looseEndPose(_ walk: WalkResult) -> PiecePose? {
        if let index = effectiveSelection(walk), walk.openEnds.indices.contains(index) {
            return walk.openEnds[index]
        }
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
                for id in run { game.editorAppend(id) }
            }
        default:
            // Nothing when there's no run to take: the reason already shows in the
            // hint line, and a dead button on the map would just be clutter.
            EmptyView()
        }
    }

    private func mapAction(
        _ symbol: String, tint: Color, label: LocalizedStringKey, action: @escaping () -> Void
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
        }
        .accessibilityLabel(Text(label, bundle: .module))
    }
}
