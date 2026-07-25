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
        guard let i = effectiveSelection(walk), walk.openEnds.indices.contains(i) else {
            return closedLoopHint(layout)
        }
        let end = walk.openEnds[i]
        let gap = layout.closureGap(from: end)
        guard let advice = advice(for: gap, facing: end.heading) else { return nil }
        let parts = gapParts(gap)
        // The search's verdict lives on the Close button, not here — this line
        // just measures the gap and says which kind of edit closes it.
        guard !parts.isEmpty else { return "Not closed — \(advice)" }
        return "Gap \(parts.joined(separator: " + ")) — \(advice)"
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

    /// The search's verdict, as a button: tap to take a found run, or a disabled
    /// label saying the search didn't find one within its depth. Showing the
    /// limit here (rather than nothing) is the point — silence reads as "this
    /// track can never close", when it only means "not in N pieces".
    @ViewBuilder var closeButton: some View {
        switch closingOutcome {
        case .found(let run) where !run.isEmpty:
            Button {
                for id in run { game.editorAppend(id) }
            } label: {
                Text("Close it (\(run.count))", bundle: .module)
                    .font(.callout.bold())
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.yellow.opacity(0.85), in: Capsule())
                    .foregroundStyle(.black)
            }
        case .needsMorePieces(let searched):
            Text("No close in \(searched)", bundle: .module)
                .font(.callout.bold())
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.black.opacity(0.2), in: Capsule())
                .foregroundStyle(.white.opacity(0.4))
        default:
            EmptyView()
        }
    }

    /// Put the track's share code on the clipboard — how a design leaves the
    /// device to be pasted into the repo as a built-in (or shared). Copy only:
    /// a button that also *loaded* a clipboard code could silently replace the
    /// track you're working on.
    func copyCode() {
        guard let code = game.customTrackCode() else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #endif
        copiedCode = true
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
        let end = effectiveSelection(walk).flatMap { i in
            walk.openEnds.indices.contains(i) ? walk.openEnds[i] : nil
        }
        let key = ClosingKey(pieces: game.editorLayout?.pieces ?? [], end: end)
        guard key != closingRunKey else { return }
        closingRunKey = key
        guard let layout = game.editorLayout, let end else {
            closingOutcome = nil
            return
        }
        closingOutcome = layout.closingOutcome(from: end, maxPieces: 3)
    }

    /// A unit count, trimmed to look like "2U" / "1.5U".
    func unitText(_ units: Double) -> String {
        units == units.rounded()
            ? "\(Int(units))U" : String(format: "%.1fU", units)
    }
}
