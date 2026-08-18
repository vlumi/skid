import SkidCore
import SwiftUI

extension EditorView {
    /// `off` shows no badges and selects anything; `all` badges everything; a storey
    /// badges everything and selects only that one.
    enum LevelFilter: Equatable, Hashable {
        case off
        case all
        case storey(Int)

        var showsBadges: Bool { self != .off }
        var storeyOnly: Int? {
            if case .storey(let level) = self { return level }
            return nil
        }

        /// Every state the long-press jump list offers: off, all, then each
        /// storey the track uses — the same states the cycle walks, so the two
        /// entrances can never disagree. A flat track's single storey is
        /// skipped, exactly as the cycle skips it: filtering by the only
        /// storey adds nothing over `all`.
        static func pickerOptions(usedLevels used: [Int]) -> [LevelFilter] {
            [.off, .all] + (used.count > 1 ? used.map { .storey($0) } : [])
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
