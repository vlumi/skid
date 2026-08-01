import SkidCore

/// **Selection is a piece, and it decides what the buttons act on.**
///
/// The editor used to select a loose END, which only ever answered "where does the
/// next piece go". A piece selection also answers "what does delete remove", which
/// is what makes mid-ring deletion reachable at all.
extension CouchGame {
    /// Which end of an open chain the palette builds from. The tail is the
    /// appending end (where the editor always grew); the head prepends.
    public enum BuildEnd: Equatable, Sendable {
        case head
        case tail
    }

    /// The selected piece's index, or nil. May go stale when the layout shrinks
    /// under it, so every use goes through `editorSelectedPiece`.
    public var editorSelection: Int? {
        get { selectionRaw }
        set { selectionRaw = newValue }
    }

    /// The selected index if it still points at a real piece — nil otherwise, so a
    /// stale selection is inert rather than acting on whatever took its place.
    public var editorSelectedPiece: Int? {
        guard let selectionRaw, let layout = editorLayout,
            layout.pieces.indices.contains(selectionRaw)
        else { return nil }
        return selectionRaw
    }

    /// Whether this piece has a free end the palette could build from, and which.
    /// A closed ring has none; an open chain's are its first and last pieces.
    public func editorFreeEnds(of index: Int) -> [BuildEnd] {
        guard let layout = editorLayout, layout.pieces.indices.contains(index),
            !layout.walk().openEnds.isEmpty
        else { return [] }
        var ends: [BuildEnd] = []
        if index == 0 { ends.append(.head) }
        if index == layout.pieces.count - 1 { ends.append(.tail) }
        return ends
    }

    /// **Which end is live**, or nil when nothing is. Building is a property of a
    /// selected end: with no selection there is no end to build from, so the palette
    /// greys out rather than quietly appending somewhere the author isn't looking.
    public var editorActiveEnd: BuildEnd? {
        guard let index = editorSelectedPiece else { return nil }
        let ends = editorFreeEnds(of: index)
        return ends.contains(editorBuildEnd) ? editorBuildEnd : ends.first
    }

    /// Place a palette piece at the live end — append or prepend. One entry point so
    /// the palette does not have to know which operation it is driving.
    ///
    /// **The palette speaks the author's direction.** At the head that is the
    /// reverse of the driving direction, so what is drawn and what is stored are
    /// mirrors: a left turn drawn away from the head is a right turn to a car
    /// arriving at it, and a climb away from the head is a descent into it.
    /// Reported from device — wanting an up-left ramp there meant tapping
    /// down-right, which is the stored piece rather than the drawn one.
    @discardableResult
    public func editorPlace(_ id: PieceID, pitch: Pitch = .flat) -> Bool {
        switch editorActiveEnd {
        case .tail: return editorAppend(id, pitch: pitch)
        case .head:
            let drawn = Self.asDrawnBackwards(id, pitch)
            return editorPrepend(drawn.id, pitch: drawn.pitch)
        case nil: return false
        }
    }

    /// Whether that placement would be accepted — asked of the SAME end it would
    /// land on, since a piece can fit one end and not the other, and of the piece
    /// that would actually be STORED there.
    public func editorCanPlace(_ id: PieceID, pitch: Pitch = .flat) -> Bool {
        switch editorActiveEnd {
        case .tail: return editorCanAppend(id, pitch: pitch)
        case .head:
            let drawn = Self.asDrawnBackwards(id, pitch)
            return editorCanPrepend(drawn.id, pitch: drawn.pitch)
        case nil: return false
        }
    }

    /// What the author's tap means when they are building BACKWARDS: the mirrored
    /// shape, climbing the other way. A straight and a flat pitch are their own
    /// mirrors, so this is the identity for them.
    static func asDrawnBackwards(_ id: PieceID, _ pitch: Pitch) -> (id: PieceID, pitch: Pitch) {
        let flipped: Pitch
        switch pitch {
        case .flat: flipped = .flat
        case .up: flipped = .down
        case .down: flipped = .up
        }
        return (PieceCatalog.mirrored[id] ?? id, flipped)
    }

    /// **Set or clear a piece's decal** — paint applied in place, so the geometry,
    /// the seams and every index are untouched.
    @discardableResult
    public func editorSetDecal(_ decal: Decal?, at index: Int) -> Bool {
        recordingUndo {
            guard var layout = editorLayout, layout.pieces.indices.contains(index),
                layout.decals[index] != decal
            else { return false }
            layout.decals[index] = decal
            editorLayout = layout
            return true
        }
    }

    /// Whether the track can be turned around: only a closed ring has a driving
    /// direction to flip, so the button greys out rather than refusing a tap.
    public var editorCanReverseDirection: Bool {
        guard let layout = editorLayout, layout.pieces.count > 1 else { return false }
        let walk = layout.walk()
        return walk.openEnds.isEmpty && walk.failure == nil
    }

    /// **Turn the track around** — see `TrackLayout.reverseDirection`. The start
    /// line ends up facing the other way, which is what decides the driving
    /// direction, and the grid, gates and centerline all follow from the geometry.
    @discardableResult
    public func editorReverseDirection() -> Bool {
        recordingUndo {
            guard var layout = editorLayout, layout.reverseDirection() else { return false }
            editorLayout = layout
            selectionRaw = nil  // every index moved
            return true
        }
    }

    /// Whether the selected piece can be removed — so the button can be absent
    /// rather than present and refusing.
    public var editorCanDeleteSelected: Bool {
        guard let index = editorSelectedPiece, let layout = editorLayout,
            layout.pieces.count > 1,
            layout.pieces[index] != PieceCatalog.startPieceID
        else { return false }
        guard !layout.walk().openEnds.isEmpty else { return true }  // ring: anywhere
        return index == 0 || index == layout.pieces.count - 1
    }

    /// Delete the selected piece. A closed ring cuts anywhere (rotate-then-pop, so
    /// the surviving road stays put); an open chain only at its ends, because a
    /// mid-chain cut would slide the whole tail.
    ///
    /// The start piece is never deletable — a track has to keep exactly one.
    @discardableResult
    public func editorDeleteSelected() -> Bool {
        guard let index = editorSelectedPiece, let layout = editorLayout,
            layout.pieces.count > 1,
            layout.pieces[index] != PieceCatalog.startPieceID
        else { return false }
        let open = !layout.walk().openEnds.isEmpty
        if open {
            // Ends only. The origin end is prepend's inverse; the tail is the
            // long-standing delete-last.
            guard index == 0 || index == layout.pieces.count - 1 else { return false }
        }
        // **The end keeps the selection.** Showing the build arrow and being able
        // to carry on building are properties of a SELECTED end, so deleting the
        // piece at an end hands the selection to its neighbour — which is the new
        // end. Otherwise trimming a few pieces means re-selecting between every
        // tap, which is what made it tedious.
        //
        // A ring has no ends, so the cut opens one and the survivor next to it
        // becomes the tail; anything else (or nothing left to select) clears.
        let wasHead = open && index == 0
        guard editorRemove(at: index) else { return false }
        editorSelect(neighbourAfterDelete(wasHead: wasHead))
        return true
    }

    /// **Select a piece, and take its end.** The build end is a property of the
    /// selected end, so selecting one that has exactly one free end also means
    /// "build here" — no second tap, and after a delete the new end is live
    /// immediately.
    public func editorSelect(_ index: Int?) {
        selectionRaw = index
        guard let index, let only = editorFreeEnds(of: index).first,
            editorFreeEnds(of: index).count == 1
        else { return }
        editorBuildEnd = only
    }

    /// The piece that inherits the selection after a delete: at the head, whatever
    /// is now first; at the tail (and after a ring cut, which leaves the cut at the
    /// end), whatever is now last.
    ///
    /// The start piece inherits it like any other — it is a perfectly good end to
    /// build from, it just cannot itself be deleted, and the delete button already
    /// hides itself for that.
    private func neighbourAfterDelete(wasHead: Bool) -> Int? {
        guard let layout = editorLayout, !layout.pieces.isEmpty else { return nil }
        return wasHead ? 0 : layout.pieces.count - 1
    }
}
