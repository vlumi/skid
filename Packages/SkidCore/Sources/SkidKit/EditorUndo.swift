import SkidCore

/// Undo as a stack of encoded snapshots: a layout is 32–59 bytes on the built-ins,
/// so a deep history is ~12 KB and restoring is a decode.
extension CouchGame {
    public static let undoDepth = 200

    /// Whether there is a state to go back to.
    public var editorCanUndo: Bool { !undoStack.isEmpty }
    /// Whether an undone state can be replayed.
    public var editorCanRedo: Bool { !redoStack.isEmpty }

    /// Run an edit, recording the state before it. Every mutating action goes
    /// through here so none can forget. A `false` from `body` (a refused edit)
    /// records nothing; a compound is one step because it's one `body`.
    ///
    /// Restoring deliberately does NOT come through here — recording an undo would
    /// leave it toggling between the last two states.
    @discardableResult
    func recordingUndo(_ body: () -> Bool) -> Bool {
        guard let layout = editorLayout else { return body() }
        let snapshot = TrackCode.encode(layout)
        guard body() else { return false }
        // **Keep the live ring spelled the way its code is.**
        //
        // Encoding normalizes, and snapshots are codes, so a non-canonical ring
        // came BACK from an undo re-spelled — every piece index landing on a
        // different piece, taking the selection, the gate seams and the build end
        // with it. Normalizing after each edit makes a snapshot round-trip a no-op.
        // Rotation is a re-spelling, so the road does not move.
        if let edited = editorLayout {
            let canonical = edited.normalized()  // a no-op on an open chain
            if canonical.pieces != edited.pieces {
                editorLayout = canonical
                // Rotating re-indexes every piece, so a selection kept by index
                // would silently jump to whatever piece took that slot — reported
                // as "the same piece is selected after closing, wherever I close".
                // There is nothing sensible to keep pointing at: closing a loop
                // takes away the free end that made the selection meaningful.
                selectionRaw = nil
            }
        }
        undoStack.append(snapshot)
        if undoStack.count > Self.undoDepth { undoStack.removeFirst() }
        redoStack.removeAll()  // a new edit ends the branch
        return true
    }

    /// Step back one state. No-op when there is nothing to go back to.
    public func editorUndo() {
        guard let previous = undoStack.popLast(), let layout = editorLayout else { return }
        redoStack.append(TrackCode.encode(layout))
        restore(previous)
    }

    /// Replay one undone state.
    public func editorRedo() {
        guard let next = redoStack.popLast(), let layout = editorLayout else { return }
        undoStack.append(TrackCode.encode(layout))
        restore(next)
    }

    /// Drop the history — on reset or loading another track, where undoing across
    /// the boundary would resurrect what the author left behind.
    func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func restore(_ code: String) {
        guard let layout = try? TrackCode.decode(code) else { return }
        editorLayout = layout
    }
}
