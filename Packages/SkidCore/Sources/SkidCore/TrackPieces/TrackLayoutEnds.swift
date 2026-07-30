import Foundation

/// **Growing the other end, and cutting a ring open.** The editor could only ever
/// extend the piece list's tail; these are the model operations behind editing the
/// head and the middle.
///
/// Both rest on the same property: **the road the author already drew does not
/// move.** Prepending extends *backwards* from the origin, so the origin moves and
/// the track does not. Ring deletion is rotate-then-pop, and rotation is a
/// re-spelling (see `TrackLayoutMutate`), so the survivors stay put by
/// construction rather than by re-walking and hoping.
extension TrackLayout {
    /// **Add a piece at the head**, leading into what used to be the first piece.
    ///
    /// The list grows at index 0 and `origin` moves *back* to the new piece's
    /// entry — the inverse of appending, where the list grows at the tail and the
    /// origin stays. Nothing already placed changes pose, because every existing
    /// coordinate derives from an origin that has been moved by exactly the new
    /// piece's own displacement.
    ///
    /// Heights work the same way: a pitched prepend lowers `originHeight` by the
    /// piece's climb, so the piece climbs *into* the old baseline instead of
    /// shifting every height after it.
    ///
    /// Returns false, changing nothing, when the piece has no exact inverse
    /// placement (see `entryPose(of:leadingTo:)`) — declining beats rounding,
    /// which would break the integer loop closure the whole model rests on.
    @discardableResult
    public mutating func prepend(_ id: PieceID, pitch: Pitch = .flat) -> Bool {
        guard let piece = PieceCatalog.piece(id),
            id != PieceCatalog.fitterPieceID,
            let entry = Self.entryPose(of: piece, leadingTo: origin)
        else { return false }

        insert(id, pitch: pitch, at: 0)
        origin = entry
        // The new piece's climb happens BEFORE the old first piece, so the
        // baseline it starts from is that much lower — leaving every height the
        // author already had exactly where it was.
        originHeight -= piece.heightDelta + pitch.delta
        return true
    }

    /// **Prepend a whole run** — what a compound expands to — keeping its order.
    ///
    /// Each piece is prepended in turn, so the run goes in **back to front**: the
    /// last piece of the run must end up adjacent to the old first piece, which
    /// means it is the first one prepended. Getting this backwards would reverse
    /// every hairpin and jog laid at the head.
    ///
    /// All or nothing: if any piece has no exact inverse placement the layout is
    /// left untouched, so a refused prepend cannot leave half a compound behind.
    @discardableResult
    public mutating func prependAll(_ run: [(id: PieceID, pitch: Pitch)]) -> Bool {
        guard !run.isEmpty else { return false }
        let original = self
        for step in run.reversed() {
            guard prepend(step.id, pitch: step.pitch) else {
                self = original
                return false
            }
        }
        return true
    }

    /// **Remove any piece from a closed ring**, opening it at the cut.
    ///
    /// Rotate the victim to the end, then pop it: rotation re-spells the ring
    /// without moving it, so every survivor keeps its pose. The result is an open
    /// chain with two loose ends, which the validator re-judges from scratch —
    /// including crossing legality and whether a fitter has gone stale.
    ///
    /// Returns false when there is nothing to cut (a single-piece track has to
    /// keep its start line) or the layout is not a closed ring, in which case
    /// `remove(at:)` at an end is the operation for an open chain.
    @discardableResult
    public mutating func removeFromRing(at index: Int) -> Bool {
        guard pieces.count > 1, pieces.indices.contains(index) else { return false }
        // Rotate so the victim is last. Already-last needs no rotation, and
        // `rotate(to:)` declines on an open chain, so this also filters those.
        let last = pieces.count - 1
        if index != last {
            let before = pieces
            rotate(to: (index + 1) % pieces.count)
            guard pieces != before else { return false }  // not a closed ring
        }
        remove(at: pieces.count - 1)
        return true
    }

    /// **The entry pose a piece must start at to END at `target`** — the inverse of
    /// placing it, and the whole trick behind prepending.
    ///
    /// A piece is authored in a local frame whose entry is the identity pose, so
    /// walking it from identity gives a fixed local exit. Placing it somewhere is
    /// "rotate that frame by the entry heading, then translate"; so the entry that
    /// lands the exit on `target` is found by running that backwards — rotate the
    /// local exit's *displacement* into the target's frame and subtract it.
    ///
    /// Exact or nothing. Every offset here is an integer multiple of a heading
    /// step, and `Coord` is closed under 45° rotation — but only when the point
    /// survives the √2⁄2 scale, which `canRotate45` decides. A piece whose
    /// displacement does not (an odd 45° step on an unlucky coordinate) returns
    /// nil rather than a rounded pose.
    ///
    /// Nil also for a piece the catalog cannot walk forward: a **fitter**, whose
    /// shape lives in the layout and whose exit is pinned to the inlet it closes
    /// onto, has nothing to invert.
    static func entryPose(of piece: Piece, leadingTo target: PiecePose) -> PiecePose? {
        guard let path = piece.paths.first else { return nil }
        // Walk from identity: entry at the world origin facing east.
        let localExit = path.exit(from: .origin)
        // The entry heading is whatever heading, turned by the piece's own turn,
        // gives the target heading.
        let turn = localExit.heading.step - PiecePose.origin.heading.step
        let entryHeading = target.heading.turnedRight(turn)
        // The piece's displacement, expressed in the placed frame: the local
        // displacement rotated by the entry heading.
        let steps = entryHeading.step - PiecePose.origin.heading.step
        guard localExit.position.canRotate45 || steps.isMultiple(of: 2) else { return nil }
        let displacement = localExit.position.rotated(eighths: steps)
        return PiecePose(position: target.position - displacement, heading: entryHeading)
    }
}
