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
                label: radius.label,
                onNext: { cycleRadius(by: 1) }, onPrevious: { cycleRadius(by: -1) }
            ) {
                HStack(spacing: 6) {
                    pieceButton(corner(left: true, angle: .degrees45), walk: walk, big: true)
                    pieceButton(corner(left: true, angle: .degrees90), walk: walk, big: true)
                    pieceButton(corner(left: false, angle: .degrees90), walk: walk, big: true)
                    pieceButton(corner(left: false, angle: .degrees45), walk: walk, big: true)
                }
            }
            carousel(
                label: straightLength.label,
                onNext: { cycleStraight(by: 1) }, onPrevious: { cycleStraight(by: -1) }
            ) {
                pieceButton(straight, walk: walk, big: true)
            }
        }
    }

    /// A swipeable group: its contents, the current setting underneath, and dots
    /// showing how many settings there are.
    private func carousel<Content: View>(
        label: LocalizedStringKey, onNext: @escaping () -> Void,
        onPrevious: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 3) {
            content()
            Text(label, bundle: .module)
                .font(.caption2.bold())
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    // Horizontal intent only — a vertical drag belongs to the
                    // scroll/pan underneath, not to the carousel.
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        return
                    }
                    if value.translation.width < 0 { onNext() } else { onPrevious() }
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
                pieceButton(piece, walk: walk, big: false, configures: .hotbar(slot))
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
