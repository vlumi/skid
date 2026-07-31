import Foundation

/// Where a track's red/white kerbs go, worked out from the **corners** rather
/// than from individual pieces.
///
/// A kerb isn't a property of a tile — it's a property of where the racing line
/// stresses the track, and those places straddle piece boundaries. Real circuits
/// kerb three positions relative to a corner, and only one of them is inside the
/// corner's own pieces:
///
/// - the **apex**, on the inside — where drivers cut;
/// - the **exit**, on the outside, from the apex onward — where you run wide
///   under power, which continues into whatever piece comes *next*;
/// - **both sides of a chicane**, because you cross the road through one.
///
/// Everything else gets the plain white edge line. Per-piece rules can express
/// the apex but never the exit, which is why this walks the whole ring.
public struct KerbPlan: Equatable, Sendable {
    /// How one side of one sample is decorated.
    public enum Edge: Equatable, Sendable {
        case line
        case kerb
    }

    /// Per placed piece, per sample: the style of each side.
    public var styles: [[(left: Edge, right: Edge)]]

    public static func == (lhs: KerbPlan, rhs: KerbPlan) -> Bool {
        guard lhs.styles.count == rhs.styles.count else { return false }
        for (a, b) in zip(lhs.styles, rhs.styles) {
            guard a.count == b.count else { return false }
            for (x, y) in zip(a, b) where x.left != y.left || x.right != y.right { return false }
        }
        return true
    }

    /// The style for one sample, or the plain line if it's out of range.
    public func style(piece: Int, sample: Int) -> (left: Edge, right: Edge) {
        guard styles.indices.contains(piece), styles[piece].indices.contains(sample) else {
            return (.line, .line)
        }
        return styles[piece][sample]
    }
}

extension KerbPlan {
    /// The sampling the plan is built at. Anything indexing a plan by sample
    /// number MUST sample its geometry the same way, or the styles land on the
    /// wrong stretches — which showed up as kerbs fragmenting into chunks when
    /// the renderer was densified independently.
    public static let degreesPerSample: Double = 3

    /// How far past a corner the exit kerb runs, in road widths. Corner exit is
    /// where a car runs wide under power, so the kerb stops shortly after the
    /// turn ends.
    private static let exitRun = 1.5

    /// Work out the kerbs for a walked layout.
    public static func plan(for walk: WalkResult, degreesPerSample: Double = Self.degreesPerSample)
        -> KerbPlan
    {
        let placed = walk.placed
        // Start everything as the plain line, then paint kerbs on.
        var styles: [[(left: Edge, right: Edge)]] = placed.map { piece in
            Array(
                repeating: (left: Edge.line, right: Edge.line),
                count: piece.centerlineSamples(degreesPerSample: degreesPerSample).count)
        }
        guard !placed.isEmpty else { return KerbPlan(styles: styles) }

        for corner in corners(in: placed) {
            paint(corner, into: &styles, placed: placed)
        }
        return KerbPlan(styles: styles)
    }

    /// One corner: a run of consecutive pieces turning the same way, or a single
    /// piece that turns both ways (a chicane/jog — a crossing).
    private struct Corner {
        /// Indices of the pieces that make up the turn, in walk order.
        var pieces: [Int]
        /// True when the turn is to the model's left (math-CCW).
        var left: Bool
        /// A crossing piece: kerbed on both sides, no separate exit.
        var crossing: Bool
    }

    /// Group the ring into corners. Consecutive arcs bending the same way are one
    /// corner (so a 90 built from two 45s reads as a single turn, and its apex
    /// sits in the middle rather than at each piece).
    private static func corners(in placed: [PlacedPiece]) -> [Corner] {
        var corners: [Corner] = []
        var current: Corner?
        for (index, piece) in placed.enumerated() {
            let turns =
                piece.piece.paths.first?.compactMap { segment -> Bool? in
                    if case .arc(_, _, let left) = segment { return left }
                    return nil
                } ?? []
            guard !turns.isEmpty else {
                // A straight ends the current corner. A FITTER lands here too:
                // its catalog path is a placeholder (its real shape is solved per
                // placement), so it reads as a straight — plain edge line, plus
                // whatever exit kerb the corner it terminates carries onto it, the
                // same as any straight after a corner. That is the right answer for
                // a gentle lateral jog, which is not a corner a car would cut, so
                // it is deliberate rather than an oversight to be "fixed" by
                // teaching the planner about `PlacedPiece.fitter`.
                if let corner = current { corners.append(corner) }
                current = nil
                continue
            }
            if Set(turns).count > 1 {
                // A crossing piece stands alone.
                if let corner = current { corners.append(corner) }
                corners.append(Corner(pieces: [index], left: turns[0], crossing: true))
                current = nil
                continue
            }
            let left = turns[0]
            if var corner = current, corner.left == left, !corner.crossing {
                corner.pieces.append(index)
                current = corner
            } else {
                if let corner = current { corners.append(corner) }
                current = Corner(pieces: [index], left: left, crossing: false)
            }
        }
        if let corner = current { corners.append(corner) }
        return joinAcrossTheSeam(corners, placed: placed)
    }

    /// **A corner that spans the list's seam is one corner, not two.**
    ///
    /// The grouping above walks the list linearly, so on a CLOSED ring a turn that
    /// happens to straddle the start of the list is cut in half — its apex lands in
    /// the middle of each fragment instead of the middle of the turn, and each
    /// fragment grows its own exit kerb.
    ///
    /// That made kerbs depend on how the ring was SPELLED: the same loop written
    /// from a different piece decorated differently. Measured on the flat eight, 13
    /// of its 16 rotations disagreed with the canonical one. The editor holds a
    /// ring in whatever order it was built, while copying normalizes it, so the
    /// kerbs visibly rearranged on a copy/paste round-trip.
    private static func joinAcrossTheSeam(_ corners: [Corner], placed: [PlacedPiece])
        -> [Corner]
    {
        guard corners.count > 1, let first = corners.first, let last = corners.last,
            // Only a closed ring wraps; an open chain's ends are genuinely ends.
            isClosed(placed),
            // The fragments must be the same turn, and both actual corners.
            first.left == last.left, !first.crossing, !last.crossing,
            // Adjacent in the ring: last piece of `last` meets first of `first`.
            last.pieces.last == placed.count - 1, first.pieces.first == 0
        else { return corners }
        var joined = Array(corners.dropFirst().dropLast())
        joined.append(Corner(pieces: last.pieces + first.pieces, left: first.left, crossing: false))
        return joined
    }

    /// Whether the walked pieces form a closed ring — the last piece's exit meets
    /// the first piece's entry.
    private static func isClosed(_ placed: [PlacedPiece]) -> Bool {
        guard let first = placed.first, let last = placed.last, placed.count > 1 else {
            return false
        }
        return last.exits.contains { $0 == first.entry }
    }

    /// Paint one corner's kerbs: the apex on the inside, and the exit on the
    /// outside running on into the pieces that follow.
    private static func paint(
        _ corner: Corner, into styles: inout [[(left: Edge, right: Edge)]],
        placed: [PlacedPiece]
    ) {
        // Which of the renderer's two edge arrays is the turn's INSIDE.
        //
        // The renderer's "left" array is the `dir.perpendicular` side, which for
        // an east heading is +y — *down* the y-down screen. A catalog piece named
        // "…Left" bends toward −y (up the screen, i.e. screen-left, honestly
        // named), so its inside — the apex — is on the −y side, which is the
        // renderer's "right" array. `Piece.Segment.arc(left:)` is the math-CCW
        // flag and the catalog passes `screenLeft = false` for a screen-left
        // piece, so `!corner.left` is exactly "bends toward screen-left".
        let insideIsRight = !corner.left

        if corner.crossing {
            for piece in corner.pieces {
                guard styles.indices.contains(piece) else { continue }
                for sample in styles[piece].indices {
                    styles[piece][sample] = (.kerb, .kerb)
                }
            }
            return
        }

        paintApex(corner, insideIsRight: insideIsRight, into: &styles)
        paintExit(corner, insideIsRight: insideIsRight, into: &styles, placed: placed)
    }

    /// The apex kerb: the inside of the turn, from just after the turn-in
    /// through to the corner's end.
    private static func paintApex(
        _ corner: Corner, insideIsRight: Bool, into styles: inout [[(left: Edge, right: Edge)]]
    ) {
        let total = corner.pieces.reduce(0) { $0 + (styles[safe: $1]?.count ?? 0) }
        var seen = 0
        for piece in corner.pieces {
            guard styles.indices.contains(piece) else { continue }
            for sample in styles[piece].indices {
                let along = total > 1 ? Double(seen) / Double(total - 1) : 0.5
                // From just after the turn-in, all the way to the corner's end,
                // where the exit kerb takes over on the other side. Stopping
                // short of the end (it used to end at 85%) left a visible gap in
                // the kerb line between the apex and the exit.
                if along > 0.15 {
                    if insideIsRight {
                        styles[piece][sample].right = .kerb
                    } else {
                        styles[piece][sample].left = .kerb
                    }
                }
                seen += 1
            }
        }
    }

    /// The exit kerb: OUTSIDE, from the apex onward and continuing into what
    /// follows — the run-wide-under-power kerb, and the reason this can't be
    /// decided per piece.
    private static func paintExit(
        _ corner: Corner, insideIsRight: Bool, into styles: inout [[(left: Edge, right: Edge)]],
        placed: [PlacedPiece]
    ) {
        //
        // Measured in WORLD LENGTH, not samples: a 16-sample arc and a 2-sample
        // straight cover wildly different distances, so a sample budget would run
        // the kerb most of the way round the ring.
        guard let lastPiece = corner.pieces.last else { return }
        let exitLength = Double(PieceCatalog.unit) * exitRun

        // Second half of the corner's final piece.
        if let count = styles[safe: lastPiece]?.count {
            for sample in (count / 2)..<count {
                setOutside(&styles[lastPiece][sample], insideIsRight: insideIsRight)
            }
        }

        // …then on into what follows, for `exitLength` of road.
        var remaining = exitLength
        var index = (lastPiece + 1) % placed.count
        let stopAt = corner.pieces.first ?? 0
        while remaining > 0, index != stopAt {
            guard styles.indices.contains(index) else { break }
            // Stop at the next corner — its own rules take over there.
            let bends =
                placed[index].piece.paths.first?.contains { segment in
                    if case .arc = segment { return true }
                    return false
                } ?? false
            if bends { break }
            remaining = spendExit(
                remaining, on: &styles[index], samples: placed[index].centerlineSamples(),
                insideIsRight: insideIsRight)
            index = (index + 1) % placed.count
        }
    }

    /// Kerb one piece's edge for as much of `remaining` road length as it covers,
    /// returning what's left of the budget.
    private static func spendExit(
        _ remaining: Double, on styles: inout [(left: Edge, right: Edge)], samples: [Vec2],
        insideIsRight: Bool
    ) -> Double {
        var left = remaining
        guard samples.count >= 2 else { return left }
        for sample in styles.indices {
            guard left > 0 else { break }
            setOutside(&styles[sample], insideIsRight: insideIsRight)
            if sample + 1 < samples.count {
                left -= (samples[sample + 1] - samples[sample]).length
            }
        }
        return left
    }

    /// Kerb the corner's OUTSIDE edge of one sample. (A left turn in the model
    /// renders clockwise on the y-down canvas, so its inside is screen-right and
    /// its outside screen-left.)
    private static func setOutside(
        _ style: inout (left: Edge, right: Edge), insideIsRight: Bool
    ) {
        if insideIsRight {
            style.left = .kerb
        } else {
            style.right = .kerb
        }
    }
}

extension Array {
    /// Bounds-checked read, for walking a ring where indices wrap.
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
