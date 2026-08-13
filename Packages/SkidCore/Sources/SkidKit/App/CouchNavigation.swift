import SkidCore
import SwiftUI

/// **Getting around: which screen the app is on, and how you leave it.**
///
/// Split out of `CouchGame` on the file-length limit, and it earns its own file: the
/// front-end redesign turned navigation from "one setup screen plus a race" into a
/// set of destinations with distinct ways back, and those rules are worth reading in
/// one place. See `HomeView` for the front door itself.
extension CouchGame {
    /// Back to the race options for the mode you were in — what a race's own
    /// "Setup" means, since you are most likely adjusting and going again.
    public func backToSetup() {
        phase = .setup
        session = nil
        rig = nil
        sound.stop()
    }

    /// **All the way out, to the front door.** What "Back" means from the lobby or
    /// the editor: those are destinations rather than steps in a race, so leaving one
    /// returns to the choice of what to do, not to somebody else's setup screen.
    public func backToMenu() {
        phase = .menu
        session = nil
        rig = nil
        sound.stop()
    }

    /// Open the race options. `HomeView` has already set `playerCount`, so this
    /// screen never has to ask who is playing — only what they are racing.
    public func openSetup() {
        phase = .setup
    }
}
