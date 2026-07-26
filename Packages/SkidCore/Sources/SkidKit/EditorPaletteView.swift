import SkidCore
import SwiftUI

/// The palette's buttons: the primitive set, and nothing else.
/// A carousel's geometry: one row tall, plus a sliver of the neighbours above and
/// below. That sliver is what says "drag me".
struct CarouselMetrics {
    var rowHeight: CGFloat = 64
    var peek: CGFloat = 9
    var spacing: CGFloat = 6
}

extension EditorView {
    /// **Left · right, then the straight and the ramp.**
    ///
    /// Left and right sit next to each other so they read as one mirrored pair, and
    /// **swiping them changes radius** (tight → medium → sweep) — the one axis a
    /// corner still has now that 45° is the only primitive angle. The straight has
    /// no axis left to swipe, so it's a plain button.
    func mainRow(walk: WalkResult) -> some View {
        HStack(spacing: 12) {
            carousel(
                values: CurveRadius.allCases, current: radius,
                select: { radiusRaw = $0.rawValue }
            ) { value in
                HStack(spacing: 6) {
                    cornerTile(left: true, radius: value, walk: walk)
                    cornerTile(left: false, radius: value, walk: walk)
                }
            }
            pieceButton(straight, walk: walk, big: true)
            pieceButton(EditorView.rampSentinel, walk: walk, big: true)
        }
    }

    /// A corner tile at an explicit radius, so a carousel row can show the
    /// neighbouring radii rather than only the selected one.
    private func cornerTile(left: Bool, radius: CurveRadius, walk: WalkResult) -> some View {
        pieceButton(corner(left: left, radius: radius), walk: walk, big: true)
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

    /// One palette button. Tapping places its piece. Greyed out when the piece can't
    /// be placed here — being refused with a reason beats a placement that breaks the
    /// track.
    ///
    /// Tap is the only gesture now. Long-press used to open a picker for the hotbar
    /// slots, and on device it fired unreliably; with a primitives-only palette there
    /// is nothing left to configure, so it's gone rather than fixed.
    @ViewBuilder
    func pieceButton(_ piece: PieceID, walk: WalkResult, big: Bool) -> some View {
        let ramp = piece == EditorView.rampSentinel
        let resolved = ramp ? game.editorRampPiece() : piece
        let placeable = resolved.map { game.editorCanAppend($0) } ?? false
        let side: CGFloat = big ? 64 : 44
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
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onTapGesture {
            guard placeable else { return }
            if ramp { game.editorRamp() } else { game.editorAppend(piece) }
        }
        .accessibilityLabel(Text(EditorView.pieceLabel(piece), bundle: .module))
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
