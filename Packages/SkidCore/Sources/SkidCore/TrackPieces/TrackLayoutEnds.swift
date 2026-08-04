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
    /// The list grows at index 0 and `origin` moves back by exactly the new
    /// piece's displacement, so nothing already placed changes pose.
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
        // The climb happens BEFORE the old first piece, so the baseline drops by
        // it and every height the author already had stays put.
        originHeight -= piece.heightDelta + pitch.delta
        return true
    }

    /// **Prepend a whole run** — what a compound expands to — keeping its order.
    ///
    /// Goes in **back to front**: the run's last piece ends up adjacent to the old
    /// first piece, so it is prepended first. Backwards would mirror every hairpin
    /// and jog laid at the head. All or nothing, so a refused prepend cannot leave
    /// half a compound behind.
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

    /// **Turn a closed ring around** — the same road, driven the other way.
    ///
    /// Done on the LAYOUT rather than as a compiler flag, which is what the
    /// overhaul plan sketched: the compiler already derives the centerline, the
    /// gate order and the grid from the walked pieces, so reversing the pieces
    /// gives all three and nothing downstream learns a new concept.
    ///
    /// Refused on an open chain (no settled direction yet, and it would move the
    /// end the author is working at) and on any piece without an exact mirror —
    /// the exact-or-nothing rule the rest of the model keeps.
    ///
    /// A reversed track is a DIFFERENT track: `normalized()` deliberately does not
    /// normalize reversal away, so the two spellings keep distinct codes.
    @discardableResult
    public mutating func reverseDirection() -> Bool {
        let walk = self.walk()
        guard walk.openEnds.isEmpty, walk.failure == nil, pieces.count > 1 else {
            return false
        }
        let count = pieces.count
        // Mirrored, in reverse order. Index i of the new list is old index
        // count-1-i, which is the remap every keyed field below follows.
        var flipped: [PieceID] = []
        for id in pieces.reversed() {
            guard let mirror = PieceCatalog.mirrored[id] else { return false }
            flipped.append(mirror)
        }
        let flippedPitches = (0..<count).map { index -> Pitch in
            switch pitch(at: count - 1 - index) {
            case .flat: return .flat
            case .up: return .down
            case .down: return .up
            }
        }
        // The new first piece is the old last one, entered from its own exit —
        // the ring's own geometry, so this stays exact.
        guard let last = walk.placed.last, let exit = last.exits.first else { return false }

        pieces = flipped
        pitches = Self.trimmedPitches(flippedPitches)
        origin = PiecePose(position: exit.position, heading: exit.heading.reversed)
        originHeight = last.exitHeight
        // Keyed data follows its piece to the mirrored index.
        //
        // Seams reverse with their pieces. A seam is a piece's EXIT, and the start
        // line is the start PIECE's exit by definition (`TrackValidator.gatesValid`
        // keys the finish to that index), so reversing genuinely moves the painted
        // line to the other end of the start piece. That is the correct reading: the
        // line marks where a lap ends, and driving the other way you cross the start
        // piece from its far side.
        gateSeams = gateSeams.map { count - 1 - $0 }.sorted()
        fitters = Dictionary(
            uniqueKeysWithValues: fitters.map { (count - 1 - $0.key, $0.value) })
        decals = Dictionary(
            uniqueKeysWithValues: decals.map { (count - 1 - $0.key, $0.value) })
        railed = Set(railed.map { count - 1 - $0 })
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
