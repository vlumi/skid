import SkidCore
import SwiftUI

/// The editor's actions on the layout: opening it, placing and removing pieces,
/// and marking checkpoint gates. Split from `CouchGame` to keep the file inside
/// the length budget.
extension CouchGame {
    /// Append a catalog piece to the end of the layout (extends the loose end).
    /// **Refused** if the piece would pave over the track or leave the canvas —
    /// blocking the placement beats accepting it and showing a warning that's
    /// easy to miss. Returns whether it was placed.
    @discardableResult
    public func editorAppend(_ id: PieceID) -> Bool {
        guard let layout = editorLayout else { return false }
        guard TrackValidator.canAppend(id, to: layout) else { return false }
        editorLayout?.pieces.append(id)
        // The moment the ring closes, finish the job: put default checkpoints in
        // (a closed loop with only the start line marked is unsaveable, and
        // nothing about that is the author's mistake) and center it on the
        // canvas, since a layout that grew left or up sits at negative
        // coordinates and would race letterboxed into a corner.
        if editorLayout?.walk().openEnds.isEmpty == true {
            if (editorLayout?.gateSeams.count ?? 0) < 2 { editorSeedGates() }
            editorCenterOnCanvas()
        }
        return true
    }

    /// Whether a palette piece can be placed right now — so the editor can gray
    /// out the ones that would break the track instead of letting you tap them.
    public func editorCanAppend(_ id: PieceID) -> Bool {
        guard let layout = editorLayout else { return false }
        return TrackValidator.canAppend(id, to: layout)
    }

    /// Append the context-aware ramp: up from the ground, down from the deck —
    /// with only two elevations the one button does both.
    public func editorRamp() {
        guard let layout = editorLayout, let last = layout.walk().placed.last else {
            editorAppend(PieceCatalog.ID.rampUp)
            return
        }
        // On the deck (height up) → ramp down; on the ground → ramp up.
        editorAppend(last.exitHeight > 0.5 ? PieceCatalog.ID.rampDown : PieceCatalog.ID.rampUp)
    }

    /// Move the whole layout so it sits centered on the canvas, by shifting the
    /// stored **origin** — the layout slides as one rigid thing, since every
    /// other coordinate derives from that anchor.
    ///
    /// Needed because a track is built outward from wherever the origin happens
    /// to be: a layout that grows left or up runs to negative coordinates, i.e.
    /// off the canvas, and races letterboxed into a corner (or partly offscreen).
    public func editorCenterOnCanvas() {
        guard var layout = editorLayout else { return }
        let points: [Vec2] = layout.walk().placed.flatMap { $0.centerlineSamples() }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
            let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return }
        // Leave room for the road's half-width on every side.
        let margin = Double(PieceCatalog.width) / 2
        let target = TrackValidator.canvas
        let shiftX = (target.x - (maxX - minX)) / 2 - minX
        let shiftY = (target.y - (maxY - minY)) / 2 - minY
        // The origin is exact, so shift by whole units to keep it that way.
        let unit = Double(PieceCatalog.unit)
        let steps = CoordPoint(
            Int((max(margin, shiftX) / unit).rounded()) * PieceCatalog.unit,
            Int((max(margin, shiftY) / unit).rounded()) * PieceCatalog.unit)
        layout.origin = PiecePose(
            position: layout.origin.position + steps, heading: layout.origin.heading)
        editorLayout = layout
    }

    /// Toggle a seam as a checkpoint gate. Seam 0 is the start/finish and is
    /// permanent; the rest are the author's choice, up to the 16-gate cap.
    ///
    /// A lap only counts when every gate is crossed in order, so gates are what
    /// stop a track being cut — which is why a saveable track needs at least one
    /// besides the start line.
    public func editorToggleGate(seam: Int) {
        guard var layout = editorLayout, seam != 0, seam < layout.pieces.count else { return }
        if let existing = layout.gateSeams.firstIndex(of: seam) {
            layout.gateSeams.remove(at: existing)
        } else {
            guard layout.gateSeams.count < 16 else { return }
            layout.gateSeams.append(seam)
        }
        editorLayout = layout
    }

    /// Whether a seam is currently a gate.
    public func editorIsGate(seam: Int) -> Bool {
        editorLayout?.gateSeams.contains(seam) ?? false
    }

    /// Put checkpoints in by default, evenly spaced around the ring, so a
    /// finished loop is immediately raceable instead of stuck one unmarked gate
    /// short. The author can retune them by tapping seams.
    public func editorSeedGates() {
        guard var layout = editorLayout, layout.pieces.count >= 2 else { return }
        // Three gates plus the start line reads as a lap without being fussy;
        // fall back to whatever the piece count allows on a tiny ring.
        let wanted = min(3, layout.pieces.count - 1)
        guard wanted >= 1 else { return }
        let step = Double(layout.pieces.count) / Double(wanted + 1)
        let seams = (1...wanted).map {
            max(1, min(layout.pieces.count - 1, Int(Double($0) * step)))
        }
        layout.gateSeams = [0] + Set(seams).sorted()
        editorLayout = layout
    }

    /// Remove the last piece (never the start piece — a track must keep one).
    public func editorDeleteLast() {
        guard var layout = editorLayout, layout.pieces.count > 1 else { return }
        layout.pieces.removeLast()
        // Drop any gate seam that no longer has a piece.
        layout.gateSeams = layout.gateSeams.filter { $0 < layout.pieces.count }
        editorLayout = layout
    }

    /// Start a fresh track (just the start piece).
    public func editorReset() {
        editorLayout = TrackLayout(pieces: [PieceCatalog.startPieceID], gateSeams: [0])
    }

    /// Whether the current layout is saveable (closed + valid).
    public func editorIsSaveable() -> Bool {
        guard let editorLayout else { return false }
        return TrackValidator.validate(editorLayout).isSaveable
    }
}
