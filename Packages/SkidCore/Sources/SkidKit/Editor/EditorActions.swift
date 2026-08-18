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
        recordingUndo {
            guard let layout = editorLayout else { return false }
            guard TrackValidator.canAppend(id, pitch: pitch, to: layout) else { return false }
            let firstNew = layout.pieces.count
            editorLayout?.append(contentsOf: PieceExpansion.expand(id, mode: pitch))
            railNewPieces(from: firstNew)
            followBuildEnd()
            finishIfClosed()
            return true
        }
    }

    /// **Step the trailing warp**, as one undoable edit that keeps the build end
    /// selected.
    ///
    /// Routed through the same machinery as an append rather than writing the layout
    /// directly, which is what an earlier version did — and that lost the selection
    /// every time. A warp becomes the LAST piece, so the previously selected piece
    /// stopped being the tail, `editorFreeEnds` returned nothing, and the whole
    /// palette greyed out: you could drop the road and then not build from it.
    @discardableResult
    func editorApplyWarpStep(deeper: Bool) -> Bool {
        recordingUndo {
            guard let layout = editorLayout else { return false }
            guard let stepped = deeper ? layout.warpedDeeper() : layout.warpedShallower()
            else { return false }
            editorLayout = stepped
            followBuildEnd()
            finishIfClosed()
            return true
        }
    }

    /// Append a suggested closing run **atomically**. The run was validated as a
    /// unit by the search, so it lands as a unit — applying it piece by piece
    /// would re-judge every prefix and silently drop the tail if any single
    /// step read as an overlap mid-run.
    ///
    /// **Closing is one operation.** The run fills the one gap between the two loose
    /// ends, so the end result is the same closed track whichever end the button was
    /// on — no prepend, no mirroring, no branch. Same for the fitter.
    @discardableResult
    public func editorAppendRun(_ run: [PlannedPiece]) -> Bool {
        recordingUndo {
            guard let layout = editorLayout, !run.isEmpty else { return false }
            guard TrackValidator.canAppend(run: run, to: layout) else { return false }
            let firstNew = layout.pieces.count
            editorLayout?.append(
                contentsOf: run.flatMap { PieceExpansion.expand($0.id, mode: $0.pitch) })
            railNewPieces(from: firstNew)
            finishIfClosed()
            return true
        }
    }

    /// Prepend a catalog piece at the **head** of the layout — the other end of
    /// the same operation as `editorAppend`, refused on the same grounds.
    ///
    /// The road already drawn does not move: the list grows at index 0 and the
    /// stored origin moves back by the new piece's own displacement (see
    /// `TrackLayout.prepend`). A compound goes in as its primitives, in order.
    @discardableResult
    public func editorPrepend(_ id: PieceID, pitch: Pitch = .flat) -> Bool {
        recordingUndo {
            guard var layout = editorLayout else { return false }
            guard TrackValidator.canPrepend(id, pitch: pitch, to: layout) else { return false }
            let before = layout.pieces.count
            guard layout.prependAll(PieceExpansion.expand(id, mode: pitch)) else { return false }
            // Prepend grows the list at index 0, so the NEW pieces are the leading
            // ones — the existing rails were already shifted up by the insert.
            if editorRailNewPieces {
                layout.railed.formUnion(0..<(layout.pieces.count - before))
            }
            editorLayout = layout
            followBuildEnd()
            finishIfClosed()
            return true
        }
    }

    /// Whether a palette piece can be prepended right now — the head-end twin of
    /// `editorCanAppend`, memoised the same way so the palette can gray out
    /// without validating on every SwiftUI render.
    public func editorCanPrepend(_ id: PieceID, pitch: Pitch = .flat) -> Bool {
        guard let layout = editorLayout else { return false }
        if prependVerdicts.pieces != layout.pieces
            || prependVerdicts.height != layout.originHeight
        {
            prependVerdicts = VerdictMemo(pieces: layout.pieces, height: layout.originHeight)
        }
        let key = VerdictKey(id: id, pitch: pitch)
        if let verdict = prependVerdicts.byPiece[key] { return verdict }
        let verdict = TrackValidator.canPrepend(id, pitch: pitch, to: layout)
        prependVerdicts.byPiece[key] = verdict
        return verdict
    }

    /// Remove the piece at `index`: anywhere on a **closed ring** (rotate it to the
    /// end and pop it, so the surviving road stays exactly where it was), or at
    /// either END of an open chain.
    ///
    /// A mid-chain cut is refused — it would slide the whole tail, which is never
    /// what the author means. Deleting the HEAD is prepend's inverse: the origin
    /// moves forward onto the new first piece, so again nothing already drawn moves.
    ///
    /// A checkpoint on the removed piece goes with it, silently: save-time
    /// validation already reports an under-gated track, and a warning per delete
    /// would just be noise.
    @discardableResult
    public func editorRemove(at index: Int) -> Bool {
        recordingUndo {
            guard var layout = editorLayout, layout.pieces.indices.contains(index),
                layout.pieces.count > 1
            else { return false }
            guard layout.walk().openEnds.isEmpty else {
                switch index {
                case layout.pieces.count - 1:
                    layout.removeLastPiece()
                case 0:
                    // The origin must move to what becomes piece 0, or the whole
                    // chain jumps back by the removed piece's displacement.
                    let walk = layout.walk()
                    guard walk.placed.indices.contains(1) else { return false }
                    let next = walk.placed[1]
                    layout.remove(at: 0)
                    layout.origin = next.entry
                    layout.originHeight = next.entryHeight
                default:
                    return false  // mid-chain: would slide the tail
                }
                editorLayout = layout
                return true
            }
            guard layout.removeFromRing(at: index) else { return false }
            editorLayout = layout
            return true
        }
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
        recordingUndo {
            guard var layout = editorLayout else { return false }
            layout.insert(PieceCatalog.fitterPieceID, at: layout.pieces.count)
            layout.fitters[layout.pieces.count - 1] = fitter
            if editorRailNewPieces { layout.railed.insert(layout.pieces.count - 1) }
            // The fitter must actually close the ring — it has nothing to offer a
            // track it leaves open, and the walk needs an inlet to pin its exit to.
            guard layout.walk().openEnds.isEmpty else { return false }
            editorLayout = layout
            finishIfClosed()
            return true
        }
    }

    /// Rail everything from `firstNew` to the end, if the palette's railing toggle
    /// is on. Placement paths that grow the list at index 0 (prepend) cannot use
    /// this — their new pieces are the leading ones, not the trailing ones.
    private func railNewPieces(from firstNew: Int) {
        guard editorRailNewPieces, let count = editorLayout?.pieces.count, firstNew < count
        else { return }
        editorLayout?.railed.formUnion(firstNew..<count)
    }

    /// After a placement the NEW piece is the end, so the selection follows it —
    /// otherwise it would still name the piece that used to be the end and the
    /// delete button would offer to remove the wrong one.
    private func followBuildEnd() {
        guard let layout = editorLayout, !layout.walk().openEnds.isEmpty else { return }
        selectionRaw = editorBuildEnd == .head ? 0 : layout.pieces.count - 1
    }

    /// The moment the ring closes, finish the job: seed default checkpoints (a
    /// closed loop with only the start line marked is unsaveable, and nothing
    /// about that is the author's mistake) and center it on the canvas, since a
    /// layout that grew left or up sits at negative coordinates and would race
    /// letterboxed into a corner.
    ///
    /// Deliberately NOT recorded for undo: this runs inside the edit that closed
    /// the ring, so seeding and centering are part of that one act. Their own
    /// snapshots would make closing a loop cost three undos.
    private func finishIfClosed() {
        guard editorLayout?.walk().openEnds.isEmpty == true else { return }
        // Deselect on closure (maintainer's call): the piece you were building from
        // no longer has a free end, and normalizing re-indexes the ring anyway — a
        // selection kept by index would jump to whatever piece took that slot.
        selectionRaw = nil
        editorBuildEnd = .tail
        if (editorLayout?.gateSeams.count ?? 0) < 2 { editorSeedGates() }
        centerOnCanvas()
    }

    /// Move the whole layout so it sits centered on the canvas, by shifting the
    /// stored **origin** — the layout slides as one rigid thing, since every
    /// other coordinate derives from that anchor.
    ///
    /// Needed because a track is built outward from wherever the origin happens
    /// to be: a layout that grows left or up runs to negative coordinates, i.e.
    /// off the canvas, and races letterboxed into a corner (or partly offscreen).
    ///
    /// Undoable when the author asks for it from the button; the automatic calls
    /// (closing a loop, loading a pasted track) run inside another action and are
    /// not separately recorded.
    /// **Re-center the layout on the canvas** — an internal step, not a button.
    ///
    /// There was a button for this and it has been removed: where a track sits on the
    /// canvas makes no difference to anything. `PieceCompiler.framed()` re-frames
    /// every compiled track to its own bounds, so the race sees the same road wherever
    /// it was built (measured: a rigid translation, identical canvas size), and
    /// `fitsCanvas` compares EXTENTS rather than position, so validation is
    /// position-invariant too. The only thing the position changed was the share code.
    ///
    /// Kept internal because closure still re-centers, where it does real work: it
    /// keeps a growing track from drifting into a corner and failing the size check
    /// for room it is not using.
    ///
    /// Reported as "the aim button doesn't seem to do anything", and it was worse than
    /// that — `max(margin, shift)` floored the shift at 60 units and `round(60/120)` is
    /// 1, so every press moved the track 120 units down-right whether it needed to or
    /// not: 40 units off-center before the first press, 520 after the fourth.
    /// The centering itself, so the public entry point is only the undo wrapper.
    @discardableResult
    private func centerOnCanvas() -> Bool {
        guard var layout = editorLayout else { return false }
        // Measured WITH the road's half-width, because that is what has to fit: a
        // bare centerline footprint understates the track by half a road on each side.
        let margin = Double(PieceCatalog.width) / 2
        guard let used = layout.walk().footprint(padding: margin) else { return false }
        let target = TrackValidator.canvas
        let shiftX = (target.x - used.width) / 2 - used.minX
        let shiftY = (target.y - used.height) / 2 - used.minY
        // The origin is exact, so shift by whole units to keep it that way.
        //
        // **Signed, and never floored.** This was `max(margin, shift)`, which pinned
        // a track already near the middle to a 60-unit shift — and `round(60/120)` is
        // 1, so every press moved the track 120 units down-right whether it needed to
        // or not. Measured on a three-storey track: 40 units off-center before the
        // first press, 520 after the fourth, monotonically worse. Reported as "the
        // aim button doesn't seem to do anything", because it moves the track on the
        // canvas rather than the camera, and zoomed in the canvas edges are off-screen.
        let unit = Double(PieceCatalog.unit)
        let steps = CoordPoint(
            Int((shiftX / unit).rounded()) * PieceCatalog.unit,
            Int((shiftY / unit).rounded()) * PieceCatalog.unit)
        layout.origin = PiecePose(
            position: layout.origin.position + steps, heading: layout.origin.heading)
        editorLayout = layout
        return true
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
        recordingUndo { rotateWholeTrack(eighths: eighths) }
    }

    /// The rotation itself, so `editorRotate` is only the undo wrapper.
    private func rotateWholeTrack(eighths: Int) -> Bool {
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
        // the canvas instead of leaving it at negative coordinates. Part of the
        // same edit, so not separately recorded — one undo puts the track back.
        centerOnCanvas()
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
        recordingUndo {
            guard let layout = editorLayout, canShiftHeight(steps: steps) else { return false }
            editorLayout?.originHeight =
                layout.originHeight + Double(steps) * Track.levelHeight / 2
            return true
        }
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

    /// Toggle a seam as a checkpoint gate, up to the 16-gate cap. **Only in gate
    /// mode** — outside it a seam tap means nothing, so a stray hit can't silently
    /// re-gate the track.
    ///
    /// A lap only counts when every gate is crossed in order, so gates are what
    /// stop a track being cut — which is why a saveable track needs at least one
    /// besides the start line. The start line's own seam is permanent: it IS the
    /// finish line, and it is the start piece's index, not necessarily 0.
    @discardableResult
    public func editorToggleGate(seam: Int) -> Bool {
        guard editorMode == .gate else { return false }
        return recordingUndo {
            guard var layout = editorLayout, seam < layout.pieces.count else { return false }
            let startSeam = layout.pieces.firstIndex(of: PieceCatalog.startPieceID) ?? 0
            guard seam != startSeam else { return false }
            if let existing = layout.gateSeams.firstIndex(of: seam) {
                layout.gateSeams.remove(at: existing)
            } else {
                guard layout.gateSeams.count < 16 else { return false }
                layout.gateSeams = (layout.gateSeams + [seam]).sorted()
            }
            editorLayout = layout
            return true
        }
    }

    public func editorIsGate(seam: Int) -> Bool {
        editorLayout?.gateSeams.contains(seam) ?? false
    }

    /// Put checkpoints in by default, evenly spaced around the ring, so a
    /// finished loop is immediately raceable instead of stuck one unmarked gate
    /// short. The author can retune them by tapping seams.
    public func editorSeedGates() {
        guard var layout = editorLayout, layout.pieces.count >= 2 else { return }
        // The start line's own seam is the finish line and must be gated — and it is
        // the start PIECE's index, not 0. Prepending puts pieces ahead of it, so
        // hardcoding 0 seeded a track with no finish line at all (measured: gates
        // [2, 6, 9, 12] on a ring whose start piece sat at 0).
        let start = layout.pieces.firstIndex(of: PieceCatalog.startPieceID) ?? 0
        // Three gates plus the start line reads as a lap without being fussy;
        // fall back to whatever the piece count allows on a tiny ring.
        let count = layout.pieces.count
        let wanted = min(3, count - 1)
        guard wanted >= 1 else { return }
        let step = Double(count) / Double(wanted + 1)
        // Spaced around the ring FROM the start line, so the gaps stay even
        // wherever it happens to sit.
        let seams = (1...wanted).map { (start + max(1, Int(Double($0) * step))) % count }
        layout.gateSeams = ([start] + Set(seams).subtracting([start]).sorted()).sorted()
        editorLayout = layout
    }

    /// Start a fresh track (just the start piece). **Undoable** — it throws away
    /// everything the author built, which is exactly the edit that most needs
    /// taking back.
    public func editorReset() {
        recordingUndo {
            editorLayout = TrackLayout(pieces: [PieceCatalog.startPieceID], gateSeams: [0])
            return true
        }
    }

    public func editorIsSaveable() -> Bool {
        guard let editorLayout else { return false }
        return TrackValidator.validate(editorLayout).isSaveable
    }
}
