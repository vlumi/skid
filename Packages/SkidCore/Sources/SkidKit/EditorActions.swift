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
    ///
    /// A compound (90°, hairpin, chicane, jog) goes in as the primitives it is
    /// made of: still one tap and one undo step's worth of intent, but the layout
    /// holds primitives so its seams are addressable — which is what puts a
    /// checkpoint at a hairpin's apex — and the share code packs it back to a
    /// single byte.
    @discardableResult
    public func editorAppend(_ id: PieceID, pitch: Pitch = .flat) -> Bool {
        guard let layout = editorLayout else { return false }
        guard TrackValidator.canAppend(id, pitch: pitch, to: layout) else { return false }
        editorLayout?.append(contentsOf: PieceExpansion.expand(id, mode: pitch))
        finishIfClosed()
        return true
    }

    /// Append a suggested closing run **atomically**. The run was validated as a
    /// unit by the search, so it lands as a unit — applying it piece by piece
    /// would re-judge every prefix and silently drop the tail if any single
    /// step read as an overlap mid-run.
    @discardableResult
    public func editorAppendRun(_ run: [PlannedPiece]) -> Bool {
        guard let layout = editorLayout, !run.isEmpty else { return false }
        guard TrackValidator.canAppend(run: run, to: layout) else { return false }
        editorLayout?.append(
            contentsOf: run.flatMap { PieceExpansion.expand($0.id, mode: $0.pitch) })
        finishIfClosed()
        return true
    }

    /// Close the loop with a **fitting piece**: place it and store its solved
    /// shape, which is the only piece whose geometry lives in the layout rather
    /// than the catalog (see `Fitter`).
    ///
    /// Solved here, once, on this device — never re-derived when a code is decoded,
    /// because `sin`/`atan2` are not required to be correctly rounded and
    /// deterministic lockstep cannot absorb an ULP of disagreement.
    @discardableResult
    public func editorAppendFitter(_ fitter: Fitter) -> Bool {
        guard var layout = editorLayout else { return false }
        layout.pieces.append(PieceCatalog.fitterPieceID)
        layout.fitters[layout.pieces.count - 1] = fitter
        // The fitter must actually close the ring — it has nothing to offer a
        // track it leaves open, and the walk needs an inlet to pin its exit to.
        guard layout.walk().openEnds.isEmpty else { return false }
        editorLayout = layout
        finishIfClosed()
        return true
    }

    /// The moment the ring closes, finish the job: put default checkpoints in
    /// (a closed loop with only the start line marked is unsaveable, and
    /// nothing about that is the author's mistake) and center it on the
    /// canvas, since a layout that grew left or up sits at negative
    /// coordinates and would race letterboxed into a corner.
    private func finishIfClosed() {
        guard editorLayout?.walk().openEnds.isEmpty == true else { return }
        if (editorLayout?.gateSeams.count ?? 0) < 2 { editorSeedGates() }
        editorCenterOnCanvas()
    }

    /// Whether a palette piece can be placed right now — so the editor can gray
    /// out the ones that would break the track instead of letting you tap them.
    ///
    /// Memoised per layout: SwiftUI re-renders the palette on ANY state change —
    /// every frame of a carousel drag included — and each render asks this for
    /// every button. The verdicts only change when the pieces do, so answering
    /// from the memo keeps drag frames free of validation work.
    public func editorCanAppend(_ id: PieceID, pitch: Pitch = .flat) -> Bool {
        guard let layout = editorLayout else { return false }
        if appendVerdicts.pieces != layout.pieces {
            appendVerdicts = (layout.pieces, [:])
        }
        let key = VerdictKey(id: id, pitch: pitch)
        if let verdict = appendVerdicts.byPiece[key] { return verdict }
        let verdict = TrackValidator.canAppend(id, pitch: pitch, to: layout)
        appendVerdicts.byPiece[key] = verdict
        return verdict
    }

    /// One placement question: which piece, at what pitch.
    struct VerdictKey: Hashable {
        var id: PieceID
        var pitch: Pitch
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

    /// Turn the whole layout 45° about its own center, by rotating the stored
    /// **origin** — the same rigid-body trick as `editorCenterOnCanvas`, since
    /// every other coordinate derives from that one anchor.
    ///
    /// This is a real shaping tool, not just cosmetics. The canvas rule limits
    /// the layout's *bounding box*, and rotating TRADES one axis for the other:
    /// a diagonal footprint measuring 1158 × 1158 becomes 1539 × 480 at 45°.
    /// Against a non-square limit that can turn "doesn't fit" into "fits" —
    /// and, just as easily, the other way round, so it's offered as something to
    /// try rather than a guaranteed fix.
    ///
    /// Exact by construction: `Heading` is eight 45° steps and `Coord` is closed
    /// under 45° rotation, so this introduces no drift and loop closure stays
    /// integer-exact.
    /// Refused (returning false) if a 45° step would land the origin off the
    /// exact ring — better to decline than to silently round and break the
    /// integer loop closure everything else depends on.
    @discardableResult
    public func editorRotate(eighths: Int = 1) -> Bool {
        guard var layout = editorLayout else { return false }
        let origin = layout.origin
        guard origin.position.canRotate45 || eighths.isMultiple(of: 2) else { return false }

        // Rotate the origin about the world origin — exactly — then let the
        // re-center below slide the whole thing back into view. Turning about
        // the footprint's own center would need a half-unit pivot, which is
        // exactly what the ring can't represent.
        layout.origin = PiecePose(
            position: origin.position.rotated(eighths: eighths),
            heading: origin.heading.turnedLeft(eighths))
        editorLayout = layout
        // Rotating swings the track into another quadrant, so bring it back onto
        // the canvas instead of leaving it at negative coordinates.
        editorCenterOnCanvas()
        return true
    }

    /// Raise or lower the WHOLE track by half a level — the lattice step, so
    /// every height stays on it.
    ///
    /// Nothing but the baseline moves: each piece's height derives from it by
    /// pitch, so the shape is untouched and loop closure can't drift. Refused
    /// when any part of the track would leave the world's storeys, which is
    /// what `canShiftHeight` reports so the buttons can gray out instead of
    /// failing silently — in practice a track that already climbs a full level
    /// cannot move at all.
    @discardableResult
    public func editorShiftHeight(steps: Int) -> Bool {
        guard let layout = editorLayout, canShiftHeight(steps: steps) else { return false }
        editorLayout?.originHeight = layout.originHeight + Double(steps) * Track.levelHeight / 2
        return true
    }

    /// Whether shifting by `steps` half-levels keeps every piece in range.
    public func canShiftHeight(steps: Int) -> Bool {
        guard let layout = editorLayout else { return false }
        let delta = Double(steps) * Track.levelHeight / 2
        let placed = layout.walk().placed
        guard !placed.isEmpty else { return false }
        // Both ends of every piece: a climb's low end can hit the floor while
        // its high end is still short of the ceiling.
        return placed.allSatisfy {
            Track.withinLevels($0.entryHeight + delta)
                && Track.withinLevels($0.exitHeight + delta)
        }
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
        layout.removeLastPiece()
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
