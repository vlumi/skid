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

    /// Place a palette piece at the chosen end — append or prepend. One entry point
    /// so the palette does not have to know which operation it is driving.
    @discardableResult
    public func editorPlace(_ id: PieceID, pitch: Pitch = .flat) -> Bool {
        switch editorBuildEnd {
        case .tail: return editorAppend(id, pitch: pitch)
        case .head: return editorPrepend(id, pitch: pitch)
        }
    }

    /// Whether that placement would be accepted — asked of the SAME end it would
    /// land on, since a piece can fit one end and not the other.
    public func editorCanPlace(_ id: PieceID, pitch: Pitch = .flat) -> Bool {
        switch editorBuildEnd {
        case .tail: return editorCanAppend(id, pitch: pitch)
        case .head: return editorCanPrepend(id, pitch: pitch)
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
        guard editorRemove(at: index) else { return false }
        selectionRaw = nil  // it pointed at a piece that is gone, and indices shifted
        return true
    }
}
