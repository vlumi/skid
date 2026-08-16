import SkidCore
import SwiftUI

/// The editor's closure advice: how far the selected loose end is from closing,
/// which kind of edit gets it there, and the "Close it" suggestion. Split from
/// `EditorView` to keep it inside the length budget — and because it's the part
/// that has needed the most iteration to phrase honestly.
extension EditorView {
    /// How far the selected loose end is from closing, in the unit system — so
    /// a stuck author can see *what kind* of gap they have. An axis-only gap is
    /// fixable with straights; a gap carrying a √2 part never is, and needs
    /// diagonal travel (a mirrored chicane, a 45° dogleg) to cancel.
    /// Returns nil when there's nothing specific to report (fall back to the
    /// generic, localized hint).
    func closureHint(_ walk: WalkResult) -> String? {
        let layout = game.editorLayout ?? TrackLayout(pieces: [PieceCatalog.startPieceID])
        guard let end = buildEndPose(walk) else { return closedLoopHint(layout) }
        // Being out of ROOM outranks the gap: when every piece is grayed out,
        // the gap reading is useless advice ("turn 180° left" — with what?).
        // Without this, a size-blocked palette had no explanation at all.
        if let full = sizeLimitHint(walk) { return full }
        // The gap is always measured the way traffic FLOWS — from the tail's exit
        // to the head's entry. Building at the head does not change the gap, only
        // which end you are adding pieces to, so measure the same span either way
        // rather than from the head outwards (which read as a 180° turn).
        let flowEnd = walk.openEnds.last ?? end
        let gap = layout.closureGap(from: flowEnd)
        guard let advice = advice(for: gap, facing: flowEnd.heading) else { return nil }
        let parts = gapParts(gap)
        // The search's verdict now belongs here. It used to sit on the Close
        // button, which has moved onto the map and only appears when there IS a
        // run to take — so without this the "searched N pieces and found nothing"
        // limit would go unreported, and silence reads as "this can never close"
        // when it only means "not within N".
        var line =
            parts.isEmpty
            ? "Not closed — \(advice)" : "Gap \(parts.joined(separator: " + ")) — \(advice)"
        // The pose advice is height-blind, and a loose end at the wrong HEIGHT
        // can't mate the start no matter how the shapes line up — a pitched-up
        // clover read "straights will close it" while every flat piece was
        // rightly refused. Say the missing half, measured against the layout's
        // own baseline: a track raised as a whole is already home at height 1,
        // and telling it to "descend to ground" was simply wrong.
        if let last = walk.placed.last {
            let offset = last.exitHeight - layout.originHeight
            if offset > 0.001 {
                line += " · descend to the start height"
            } else if offset < -0.001 {
                line += " · climb to the start height"
            }
        }
        if case .needsMorePieces(let searched) = closingOutcome {
            line += " · no close in \(searched)"
        }
        return line
    }

    /// Why the palette is grayed out, when the reason is SIZE rather than shape.
    ///
    /// The canvas rule caps the track's *bounding box*, not its position — so
    /// "off the canvas" is the wrong mental model and moving the track doesn't
    /// help. Rotating can: it TRADES one axis for the other (a diagonal
    /// footprint measuring 1158 × 1158 becomes 1539 × 480 at 45°), which can fit
    /// a non-square limit that the current orientation doesn't. It's a trade,
    /// not a saving — so the advice offers it as something to try, alongside the
    /// reliable fix of shortening a run. Names the full axis, matching what the
    /// drawn bounds highlight.
    ///
    /// Nil unless the room really has run out, so this never crowds out the gap
    /// reading during normal building.
    func sizeLimitHint(_ walk: WalkResult) -> String? {
        guard let used = walk.paddedFootprint() else { return nil }
        let limit = TrackValidator.canvas
        // The smallest piece that could still be laid: if even a short straight
        // won't fit, the palette is empty for size reasons and needs saying.
        let smallest = Double(PieceCatalog.shortStraight)
        let freeX = limit.x - used.width
        let freeY = limit.y - used.height
        guard freeX < smallest || freeY < smallest else { return nil }
        let axis: String
        if freeX < smallest && freeY < smallest {
            axis = "Out of room"
        } else {
            axis = freeX < smallest ? "Out of room across" : "Out of room down"
        }
        return "\(axis) — shorten a run, or try rotating"
    }

    /// The gap's components, in the currencies the unit system spends.
    func gapParts(_ gap: ClosureGap) -> [String] {
        var parts: [String] = []
        // Axis offsets, named by compass direction (screen y grows downward).
        if gap.axisX != 0 {
            parts.append("\(unitText(abs(gap.axisX))) \(gap.axisX > 0 ? "E" : "W")")
        }
        if gap.axisY != 0 {
            parts.append("\(unitText(abs(gap.axisY))) \(gap.axisY > 0 ? "S" : "N")")
        }
        if gap.needsDiagonalTravel {
            parts.append("\(unitText(max(abs(gap.diagonalX), abs(gap.diagonalY)))) diagonal")
        }
        return parts
    }

    /// Which edit closes the gap, in words. Nil when there's nothing to do.
    func advice(for gap: ClosureGap, facing heading: Heading) -> String? {
        switch gap.remedy(facing: heading) {
        case .closed:
            return nil
        case .turn(let eighths):
            // Report the shorter way round, so 7 eighths reads as "45° left".
            let left = eighths <= 4
            return "turn \((left ? eighths : 8 - eighths) * 45)° \(left ? "left" : "right")"
        case .straights:
            return "straights will close it"
        case .tooLong:
            return "overshot — shorten a run instead"
        case .balanceDiagonals:
            return "45s must cancel — pair them opposite, or 8 round the loop"
        }
    }

    /// The ring has no loose end, so anything still unsaveable is a rule other
    /// than geometry — name it, instead of telling the author to extend an end
    /// that isn't there.
    /// Geometry problems come FIRST. A missing checkpoint is a one-tap fix and
    /// is present on every track the editor builds (it seeds only seam 0), so
    /// reporting it first permanently masked the real blockers — a self-crossing
    /// track showed "mark a checkpoint to finish" and looked finishable.
    func closedLoopHint(_ layout: TrackLayout) -> String? {
        let problems = TrackValidator.validate(layout).problems
        for problem in problems {
            if case .unclosedHeight = problem { return "Ramp back down before closing" }
            // A fitting piece whose shape no longer spans its gap — its
            // neighbors were edited after it was solved. Re-solving is the fix,
            // which is what re-closing does.
            if case .unsolvedFitter = problem { return "Close the loop again to refit" }
        }
        if problems.contains(.overlap) { return "The track crosses itself — reshape it" }
        if problems.contains(.offCanvas) { return "The track runs off the canvas" }
        if problems.contains(.gates) { return "Tap a joint to add a checkpoint" }
        return nil
    }

    /// Recompute the "Close it" suggestion if the layout or selection changed.
    /// Called from a task, never from `body`: the search is far too slow to run
    /// per frame (it made the editor jam).
    func refreshClosingRun(_ walk: WalkResult) {
        let end = buildEndPose(walk)
        let key = ClosingKey(pieces: game.editorLayout?.pieces ?? [], end: end)
        guard key != closingRunKey else { return }
        closingRunKey = key
        guard let layout = game.editorLayout, let end else {
            closingOutcome = nil
            return
        }
        // **Always searched from the tail, offered at either end.** The gap is one
        // span — the run that fills it is the same set of pieces whichever end you
        // attach it to, and the road comes out identical (verified against the
        // normalized codes). So the search only ever runs forward, and the head just
        // prepends the same run.
        //
        // Searching from the HEAD instead is what cannot work: the search walks
        // forward onto the layout's origin, so from the head it measured the wrong
        // direction entirely and read "turn 180° — no close in 3".
        guard game.editorActiveEnd != nil else {
            closingOutcome = nil  // nothing selected: no end to close from
            return
        }
        closingOutcome = layout.closingOutcome(from: walk.openEnds.last ?? end, maxPieces: 3)
    }

    /// A unit count, trimmed to look like "2U" / "1.5U".
    func unitText(_ units: Double) -> String {
        units == units.rounded()
            ? "\(Int(units))U" : String(format: "%.1fU", units)
    }
}
