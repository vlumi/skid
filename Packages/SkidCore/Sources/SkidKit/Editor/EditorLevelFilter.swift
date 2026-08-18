import SkidCore
import SwiftUI

extension EditorView {
    /// `off` shows no badges and selects anything; `all` badges everything; a storey
    /// badges everything and selects only that one.
    enum LevelFilter: Equatable {
        case off
        case all
        case storey(Int)

        var showsBadges: Bool { self != .off }
        var storeyOnly: Int? {
            if case .storey(let level) = self { return level }
            return nil
        }

        /// The next filter in the cycle, given the storeys the track uses —
        /// offering "level 2" on a flat track is a state that selects nothing.
        func next(usedLevels used: [Int]) -> LevelFilter {
            switch self {
            case .off:
                // Even on a flat track: the mode is something you keep ON while
                // building a multi-level track, so it must be reachable BEFORE
                // the first climb exists — a button that does nothing until
                // level 1 appears reads as broken.
                return .all
            case .all:
                // A flat track has one storey, so filtering by it adds nothing
                // over `all` — skip straight back to off.
                return used.count > 1 ? used.first.map { .storey($0) } ?? .off : .off
            case .storey(let level):
                guard let at = used.firstIndex(of: level), at + 1 < used.count else {
                    return .off
                }
                return .storey(used[at + 1])
            }
        }
    }
}
