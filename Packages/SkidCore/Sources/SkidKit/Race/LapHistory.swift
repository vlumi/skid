import SkidCore

/// **Which laps a time-trial chip lists, and whether the best needs pinning.**
///
/// A trial laps until you stop, so the history cannot all be shown — an unbounded column
/// runs off the bottom of a phone. This picks the window: the most recent `limit` laps,
/// plus the best lap pinned separately once it has scrolled out of that window, so the
/// number you are chasing never disappears from the screen.
///
/// Split out of the view because it is the part that can be wrong. The rows themselves are
/// SwiftUI the suite cannot drive; *which* rows, and their lap numbers, is arithmetic.
struct LapHistory: Equatable {
    /// A lap as it will be listed: its 1-based number, its time, and whether it is the best.
    struct Row: Equatable {
        var number: Int
        var ticks: Tick
        var isBest: Bool
    }

    /// The recent laps, oldest first — lap numbers are the real ones, not window offsets.
    var rows: [Row]
    /// The best lap, only when it is NOT among `rows` and so needs its own pinned line.
    var pinnedBest: Tick?

    /// - Parameter limit: how many recent laps to list. Non-positive lists none.
    init(lapTimes: [Tick], limit: Int) {
        let best = lapTimes.min()
        // **The star marks ONE lap, the first to set the time.** Marking every lap equal
        // to the best is the obvious reading of "is best" and it is wrong in practice: a
        // steady driver repeats their fastest time, and a real 8-lap run came back with
        // three starred rows, which tells the player nothing.
        let bestIndex = best.flatMap { time in lapTimes.firstIndex(of: time) }
        // Typed as a SLICE deliberately: `lapTimes[lapTimes.endIndex...]` rather than a
        // literal `[]` for the empty case, because an `Array` would renumber from zero and
        // every lap label past the first window would be wrong.
        let window: ArraySlice<Tick> =
            limit > 0 ? lapTimes.suffix(limit) : lapTimes[lapTimes.endIndex...]
        // A slice keeps its indices into the original array, so subscripting the SLICE
        // (never a re-enumeration of it) is what keeps lap numbers true once the window
        // has slid past the start of the run.
        rows = window.indices.map {
            Row(number: $0 + 1, ticks: window[$0], isBest: $0 == bestIndex)
        }
        // Pinned when the lap that SET the best has scrolled away. Keyed on that lap
        // rather than on the time, so a later lap that merely equalled it does not hide
        // the pin and leave the column with no star at all.
        pinnedBest = bestIndex.flatMap { window.indices.contains($0) ? nil : lapTimes[$0] }
    }
}
