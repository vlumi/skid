import Foundation

/// **Walking a layout**: turning a list of piece ids into placed pieces with
/// exact poses. The one place coordinates are derived, so everything downstream
/// reads the same geometry.
extension TrackLayout {
    /// Walk the piece list from the origin, placing each piece and threading
    /// poses. Forks push their extra exit onto a stack of loose ends; a piece
    /// extends the current loose end, and when an exit lands exactly on an
    /// open end it auto-mates (that end is consumed). Pure and deterministic —
    /// no coordinates are read from storage, only derived here.
    public func walk() -> WalkResult {
        guard !pieces.isEmpty else {
            return WalkResult(placed: [], openEnds: [], failure: .emptyLayout)
        }

        var placed: [PlacedPiece] = []
        // Inlets a loose end can close onto: the start line (the origin, its
        // heading pointing INTO the first piece) plus each fork's not-yet-
        // continued exit. A loose end "mates" when it lands on an inlet exactly
        // and head-on. The origin inlet stays available the whole walk so a
        // ring closes onto it.
        var inlets: [(pose: PiecePose, height: Double)] = [(origin, originHeight)]
        // Loose ends still to be extended (LIFO stack). Start at the origin.
        var ends: [(pose: PiecePose, height: Double)] = [(origin, originHeight)]
        var seam = 0

        for (index, id) in pieces.enumerated() {
            guard let piece = PieceCatalog.piece(id) else {
                return WalkResult(
                    placed: placed, openEnds: ends.map(\.pose), failure: .unknownPiece(id))
            }
            // Continue the current loose end (LIFO — a fork's branch is
            // finished before returning to the trunk's pushed exit).
            guard let current = ends.popLast() else { break }  // stranded piece
            let entry = current.pose
            let entryHeight = current.height
            // **A fitter's exit is the pose it closes onto, taken exactly.**
            //
            // Every other piece computes its exit by walking segments through the
            // `Coord` ring, which is exact by construction. A fitter cannot: its
            // arc angle is free, so its true exit is irrational and has no
            // representation there. Rather than admit floats into the pose graph
            // (and so into port mating and loop closure, whose exactness is why
            // bridges mate and codes are portable), a fitter is *defined* by where
            // it lands: it closes onto an existing inlet, and that inlet's pose —
            // already exact — becomes its exit. The stored `Fitter` then describes
            // only HOW it gets there, for drawing and for the centerline.
            //
            // The consequence is that a fitter must have somewhere to close onto.
            // One that doesn't is a loose end the validator reports, not a shape
            // the walk invents.
            let exits: [PiecePose]
            if id == PieceCatalog.fitterPieceID {
                guard let target = fitterTarget(from: entry, inlets: inlets) else {
                    return WalkResult(
                        placed: placed, openEnds: ends.map(\.pose) + [entry],
                        failure: .unknownPiece(id))
                }
                exits = [target]
            } else {
                exits = piece.paths.map { $0.exit(from: entry) }  // chain fold
            }
            let vertical = verticalOf(piece, at: index, entryHeight: entryHeight)
            var placement = PlacedPiece(
                id: id, piece: piece, entry: entry, exits: exits,
                entryHeight: entryHeight, entrySeam: seam, pitch: vertical.pitch,
                warpDrop: vertical.drop)
            placement.fitter = id == PieceCatalog.fitterPieceID ? fitters[index] : nil
            applyEasing(to: &placement, next: piece, placed: &placed)
            placed.append(placement)
            seam += 1

            let exitHeight = placement.exitHeight
            // A fork's SECOND+ exits become both new loose ends AND inlets
            // (a later branch can rejoin them); the FIRST exit is the one we
            // continue next. Auto-mate each exit that lands on an existing
            // inlet at the same height instead of pushing it.
            for (k, exitPose) in exits.enumerated() {
                if let hit = inlets.firstIndex(where: {
                    mate(exitPose, $0.pose) && abs(exitHeight - $0.height) < 0.001
                }) {
                    inlets.remove(at: hit)  // closed this joint
                } else {
                    ends.append((exitPose, exitHeight))
                    if k > 0 { inlets.append((exitPose, exitHeight)) }
                }
            }
        }

        return WalkResult(placed: placed, openEnds: ends.map(\.pose), failure: nil)
    }

    /// **Where a climb eases, and where it stays a wedge.**
    ///
    /// A climb runs straight THROUGH into a neighbour climbing the same way, so a
    /// full climb split into halves is one S-curve rather than a terrace with a shelf
    /// at the apex. (Sequence order is placement order — forks are Phase B, so
    /// neighbours are i±1.)
    ///
    /// And **a climb with nothing above it is a launch lip**, which keeps its full
    /// slope. The eased top exists because a bridge ramp must arrive LEVEL: it used
    /// to throw the car at the top of every bridge. But that easing flattens the last
    /// stretch to almost horizontal — measured at 0.007 of a level over the final 5%,
    /// where the raw slope is 0.05 — so a ramp ending at a lip launched nothing and
    /// the car merely drove off an edge.
    ///
    /// What makes it a lip is that the road does not continue at the climb's height:
    /// either a gap follows, or a warp drops the road below it. Both mean there is no
    /// deck to meet, so carrying the slope to the edge is the honest shape.
    private func applyEasing(
        to placement: inout PlacedPiece, next piece: Piece, placed: inout [PlacedPiece]
    ) {
        guard let previous = placed.last else { return }
        if continues(previous.climb, placement.climb) {
            placement.easeIn = false
            placed[placed.count - 1].easeOut = false
        }
        if previous.climb > 0, piece.gapSpan != nil || placement.climb < 0 {
            placed[placed.count - 1].easeOut = false
        }
    }

    /// **How one placement runs vertically**: the pitch it is actually laid at, and
    /// a warp's drop.
    ///
    /// **A gap is always flat.** Its two ends are the lip and the landing, so a
    /// pitched gap puts one half a level above the other and the piece stops being a
    /// hole you cross. Refused here, at the one place pitch enters a placement,
    /// rather than asked of the editor: a gap laid while the build pitch happened to
    /// be "up" climbed and every piece after it inherited that height — reported from
    /// device, where it read as "the jump is just a ramp".
    ///
    /// **A warp only ever drops**, and never below the world's floor: clamped so a
    /// layout with a too-deep warp still walks (it lands on the floor) instead of
    /// producing road under the world.
    private func verticalOf(
        _ piece: Piece, at index: Int, entryHeight: Double
    ) -> (pitch: Pitch, drop: Double) {
        let laidPitch = piece.gapSpan == nil ? pitch(at: index) : .flat
        guard piece.kind == .warp else { return (laidPitch, 0) }
        let floor = Track.levelHeight * Double(Track.lowestLevel)
        return (laidPitch, max(floor - entryHeight, warpDrop(at: index)))
    }

    /// Two consecutive climbs continue each other when both run the same way.
    private func continues(_ a: Double, _ b: Double) -> Bool {
        a != 0 && b != 0 && (a > 0) == (b > 0)
    }

    /// A loose end mates an inlet when their poses are **identical** — same
    /// position and same heading. The walk is forward-driven: an inlet stores
    /// the direction traffic flows *into* the joint (the origin faces the way
    /// piece 0 drives away; a fork branch-exit faces the way it drives on), so
    /// a returning end closes by flowing in the *same* direction, not head-on.
    private func mate(_ end: PiecePose, _ inlet: PiecePose) -> Bool {
        end == inlet
    }
}

/// The result of walking a layout: every piece placed in exact coordinates,
/// plus whatever ports are still open (loose ends) and any error that stopped
/// the walk. A fork-free ring that closes leaves `openEnds` empty.
public struct WalkResult: Equatable, Sendable {
    public enum Failure: Equatable, Sendable {
        case unknownPiece(PieceID)
        case emptyLayout
    }

    public var placed: [PlacedPiece]
    /// Poses still awaiting a mate (loose ends). Empty ⇒ fully connected.
    public var openEnds: [PiecePose]
    public var failure: Failure?

    public var isConnected: Bool { failure == nil && openEnds.isEmpty }

    /// **The ground the road covers**, centerline bounds grown by `padding`.
    ///
    /// One definition, because the editor's canvas box, its out-of-room hint and
    /// its centering all describe the SAME rule and have to agree — they were
    /// three separate transcriptions of it. Nil for a layout with no samples.
    public func footprint(padding: Double = 0) -> Rect? {
        let points = placed.flatMap { $0.centerlineSamples() }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
            let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return nil }
        return Rect(
            x: minX - padding, y: minY - padding,
            width: (maxX - minX) + 2 * padding, height: (maxY - minY) + 2 * padding)
    }

    /// The footprint padded by the road's half-width — the extent the validator
    /// measures against the canvas.
    public func paddedFootprint() -> Rect? {
        footprint(padding: Double(PieceCatalog.width) / 2)
    }
}
