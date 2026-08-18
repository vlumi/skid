import SkidCore
import SwiftUI

/// The palette's placement verdicts, memoised — split from `EditorActions.swift`
/// on the file-length budget.
extension CouchGame {
    /// Whether a palette piece can be placed right now — so the editor can gray
    /// out the ones that would break the track instead of letting you tap them.
    ///
    /// Memoised per layout: SwiftUI re-renders the palette on ANY state change —
    /// every frame of a carousel drag included — and each render asks this for
    /// every button. The verdicts only change when the pieces do, so answering
    /// from the memo keeps drag frames free of validation work.
    public func editorCanAppend(_ id: PieceID, pitch: Pitch = .flat) -> Bool {
        guard let layout = editorLayout else { return false }
        if appendVerdicts.pieces != layout.pieces
            || appendVerdicts.height != layout.originHeight
        {
            appendVerdicts = VerdictMemo(pieces: layout.pieces, height: layout.originHeight)
        }
        let key = VerdictKey(id: id, pitch: pitch)
        if let verdict = appendVerdicts.byPiece[key] { return verdict }
        let verdict = TrackValidator.canAppend(id, pitch: pitch, to: layout)
        appendVerdicts.byPiece[key] = verdict
        return verdict
    }

    /// One end's verdict cache plus the layout fingerprint it answers for. The
    /// fingerprint is the piece list AND the origin height: raising or lowering
    /// the whole track changes every verdict without touching a piece — keyed on
    /// pieces alone, a descend refused at the ground floor stayed refused after
    /// the track was raised to the top (reported: "I raised the start piece to
    /// the top level, but I can't add a ramp down from it").
    struct VerdictMemo {
        var pieces: [PieceID] = []
        var height: Double = 0
        var byPiece: [VerdictKey: Bool] = [:]
    }

    /// One placement question: which piece, at what pitch.
    struct VerdictKey: Hashable {
        var id: PieceID
        var pitch: Pitch
    }
}
