import SkidCore
import SwiftUI

/// **Launch arguments, for screenshots and automated checks.**
///
/// Split out of `CouchGame` on the file-length limit, and it is a clean subject: none of
/// this is reachable by a player, and all of it exists because `simctl` cannot tap. A
/// screen several taps in is otherwise unreachable for a screenshot.
///
///     -skid-players N        seat N people
///     -skid-ai N             any N > 0 means "fill the grid"
///     -skid-track ID         pick a track
///     -skid-mode NAME        race | timeTrial
///     -skid-setup            open the race options
///     -skid-shelf            open the editor's track list
///     -skid-edit             open the editor canvas
///     -skid-autostart        start the race, past the ready gate
///     -skid-tuning           open the tuning panel (simctl cannot shake)
///     -skid-settings         open the settings sheet
///     -skid-about            open the about sheet
extension CouchGame {
    func applyLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-skid-players"),
            index + 1 < arguments.count, let count = Int(arguments[index + 1])
        {
            playerCount = max(1, min(Self.maxLocalPlayers, count))
        }
        if let index = arguments.firstIndex(of: "-skid-ai"),
            index + 1 < arguments.count, let count = Int(arguments[index + 1])
        {
            // Kept for the screenshot/test launch arguments: any positive count means
            // "fill the grid", which is the only AI choice there is now.
            fillWithAI = count > 0
        }
        if let index = arguments.firstIndex(of: "-skid-track"), index + 1 < arguments.count {
            trackID = TrackLibrary.track(id: arguments[index + 1]).id
        }
        // Before `-skid-autostart`, which builds the race from whatever mode is set.
        if let named = Self.mode(from: arguments) {
            mode = named
        }
        // Straight to the race options, skipping the front door — for screenshots of
        // the setup screen, which is otherwise two taps in and unreachable from a
        // launch argument.
        if arguments.contains("-skid-setup") {
            phase = .setup
        }
        // Straight into the editor's track shelf, for the same reason `-skid-setup`
        // exists: it is several taps in and `simctl` cannot tap.
        // The editor canvas itself, past the shelf.
        if arguments.contains("-skid-edit") {
            phase = .editing
            showingTrackShelf = false
        }
        if arguments.contains("-skid-shelf") {
            phase = .editing
            showingTrackShelf = true
        }
        if arguments.contains("-skid-autostart") {
            startRace()
            // Screenshots/tests want a running race, not the ready gate.
            session?.started = true
        }

    }

    /// `-skid-mode NAME`, or nil when absent or unrecognized — an unknown name leaves the
    /// mode alone rather than guessing at one.
    private static func mode(from arguments: [String]) -> Mode? {
        guard let index = arguments.firstIndex(of: "-skid-mode"),
            index + 1 < arguments.count
        else { return nil }
        switch arguments[index + 1] {
        case "timeTrial": return .timeTrial
        case "race": return .race
        default: return nil
        }
    }
}
