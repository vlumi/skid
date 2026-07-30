import SkidCore

/// **Undo for the editor, as a stack of encoded snapshots.**
///
/// A whole layout encodes to well under 100 bytes, so keeping hundreds of states
/// costs nothing and restoring is just a decode. That cheapness is why the history
/// is deep rather than a token few steps.
///
/// It exists because deleting from anywhere on a ring made destructive mistakes
/// easy; undo is what makes that acceptable.
extension CouchGame {
    /// How many states the history holds. Generous on purpose — see above; the
    /// memory is a few tens of kilobytes at the very top end.
    public static let undoDepth = 200

    /// Whether there is a state to go back to.
    public var editorCanUndo: Bool { !undoStack.isEmpty }
    /// Whether an undone state can be replayed.
    public var editorCanRedo: Bool { !redoStack.isEmpty }

    /// **Run an edit, with the state before it recorded for undo.**
    ///
    /// Every mutating editor action goes through here, which is what stops any one
    /// of them from forgetting to snapshot. Two things it gets right that a
    /// snapshot-on-change observer could not:
    ///
    /// - **A refused edit leaves no trace.** `body` reports whether it did
    ///   anything, and a false pushes nothing — otherwise tapping a grayed-out
    ///   piece would fill the history with no-ops and undo would look broken.
    /// - **One tap is one step.** A compound expands to several primitives inside
    ///   a single `body`, so it undoes as the one act of intent it was.
    ///
    /// Restoring (`editorUndo`/`editorRedo`) deliberately does NOT come through
    /// here: an undo is not an edit, and recording it would leave undo toggling
    /// between the last two states forever.
    @discardableResult
    func recordingUndo(_ body: () -> Bool) -> Bool {
        guard let layout = editorLayout else { return body() }
        let snapshot = TrackCode.encode(layout)
        guard body() else { return false }
        undoStack.append(snapshot)
        if undoStack.count > Self.undoDepth { undoStack.removeFirst() }
        // A fresh edit after undoing abandons the redo tail — the standard
        // contract, and it avoids a branching history nobody asked for.
        redoStack.removeAll()
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

    /// Throw the history away — on opening a different track or starting a fresh
    /// one, where undoing across the boundary would resurrect a track the author
    /// deliberately left behind.
    func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Decode a snapshot back into the editor. A code that will not decode is a
    /// bug in encoding, not a state to limp through — but the editor is the wrong
    /// place to crash, so it is left alone.
    private func restore(_ code: String) {
        guard let layout = try? TrackCode.decode(code) else { return }
        editorLayout = layout
    }
}
