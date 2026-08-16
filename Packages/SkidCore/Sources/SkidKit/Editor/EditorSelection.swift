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
        // A trailing warp occupies no ground, so the piece before it is the tail as
        // far as the author is concerned — and selecting either must keep the palette
        // live. `>=` rather than `==` so both the warp and its road count.
        if index >= layout.lastRoadIndex { ends.append(.tail) }
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

    /// **Step the drop at the tail's warp by one level** — the down/up arrows.
    ///
    /// There is no warp to *place*: a warp occupies no length, so a piece the author
    /// has to position would be a thing with nowhere to be. The arrows maintain it
    /// instead — the first tap down appends one, later taps deepen the one already
    /// there, and shallowing it to zero removes it again. Two adjacent warps are
    /// indistinguishable from one deeper warp, so keeping a single trailing warp is
    /// what makes the layout canonical rather than merely equivalent.
    ///
    /// **Tail only.** At the head the author builds against the driving direction,
    /// where a drop away from them is a climb *into* them — and nothing lifts a car,
    /// so that road could not be driven. Returns false there rather than quietly
    /// storing the mirror.
    @discardableResult
    public func editorStepWarp(deeper: Bool) -> Bool {
        editorApplyWarpStep(deeper: deeper)
    }

    /// Whether the down/up arrow has anything to do: down always may (the world's
    /// floor clamps the walk), up only when there is a warp to shallow.
    public func editorCanStepWarp(deeper: Bool) -> Bool {
        guard editorActiveEnd == .tail, let layout = editorLayout else { return false }
        return deeper ? layout.canWarpDeeper : layout.endsInWarp
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

    /// **Toggle a piece's guard railing** — like a decal, applied in place, so the
    /// geometry, the seams and every index are untouched.
    ///
    /// Rails are per placed piece rather than per shape (see `TrackLayout.railed`),
    /// which is what makes a bridge you can drive off and a railing on flat ground
    /// both expressible.
    @discardableResult
    public func editorToggleRail(at index: Int) -> Bool {
        recordingUndo {
            guard var layout = editorLayout, layout.pieces.indices.contains(index)
            else { return false }
            if layout.railed.contains(index) {
                layout.railed.remove(index)
            } else {
                layout.railed.insert(index)
            }
            editorLayout = layout
            return true
        }
    }

    /// Whether the selected piece carries a railing, for the button's state.
    public func editorIsRailed(at index: Int) -> Bool {
        editorLayout?.isRailed(at: index) ?? false
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
            //
            // **A trailing warp does not count as the end.** It occupies no ground,
            // so the piece before it is what the author sees at the tail — and
            // requiring the literal last index made that piece undeletable from
            // above, which is how it behaved on device.
            guard index == 0 || index >= layout.lastRoadIndex else { return false }
        }
        // **The end keeps the selection.** Showing the build arrow and being able
        // to carry on building are properties of a SELECTED end, so deleting the
        // piece at an end hands the selection to its neighbor — which is the new
        // end. Otherwise trimming a few pieces means re-selecting between every
        // tap, which is what made it tedious.
        //
        // A ring has no ends, so the cut opens one and the survivor next to it
        // becomes the tail; anything else (or nothing left to select) clears.
        let wasHead = open && index == 0
        // **A warp goes with the piece it attaches to.** It is not a thing the author
        // placed — it is the preparation that lets a different height connect — so it
        // must not survive as an orphan the road no longer needs. Deleting the piece
        // before a trailing warp removes both, in one undo.
        //
        // Reported from device: the warp could only be reached from the lower end,
        // and from above neither it nor the ramp feeding it was deletable.
        let warpToo =
            index + 1 == layout.pieces.count - 1
            && layout.pieces.last == PieceCatalog.ID.warp
        if warpToo, !editorRemove(at: layout.pieces.count - 1) { return false }
        guard editorRemove(at: index) else { return false }
        editorSelect(neighborAfterDelete(wasHead: wasHead))
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

    /// **Step the selection along the ring**, wrapping at the ends.
    ///
    /// Exists for bulk property edits: railing a run of existing pieces used to mean
    /// re-aiming a tap at every piece. With a step, it is toggle-step-toggle — two taps
    /// per piece, but blind-repeatable. Steps only when something is selected: from
    /// nothing, a step has no anchor to move from.
    public func editorStepSelection(_ delta: Int) {
        guard let current = editorSelectedPiece,
            let count = editorLayout?.pieces.count, count > 0
        else { return }
        editorSelect(((current + delta) % count + count) % count)
    }

    /// The piece that inherits the selection after a delete: at the head, whatever
    /// is now first; at the tail (and after a ring cut, which leaves the cut at the
    /// end), whatever is now last.
    ///
    /// The start piece inherits it like any other — it is a perfectly good end to
    /// build from, it just cannot itself be deleted, and the delete button already
    /// hides itself for that.
    private func neighborAfterDelete(wasHead: Bool) -> Int? {
        guard let layout = editorLayout, !layout.pieces.isEmpty else { return nil }
        return wasHead ? 0 : layout.pieces.count - 1
    }
}
