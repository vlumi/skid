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

    /// **Throw away everything the app has stored, and start as if freshly installed.**
    ///
    /// A development tool (see `ResetAllData`), reached from the tuning panel: tracks,
    /// records and dials all persist, and while the game is being built they regularly
    /// need to go back to nothing.
    ///
    /// Memory is cleared before disk. Setting `editorLayout` runs a `didSet` that writes
    /// the custom slot and syncs the library, so the order looks load-bearing — but
    /// clearing it to nil is in fact safe either way: `saveCustomTrack` only *removes*
    /// the key when there is no track, and `syncEditedTrackToLibrary` returns on its
    /// `guard let layout`. Kept in this order because it stays correct if either of those
    /// ever learns to write on nil, not because it is currently load-bearing.
    public func resetAllData() {
        backToMenu()
        editorLayout = nil
        editedEntryID = nil
        library = TrackLibraryBook()
        hiscores = HiscoreBook()
        profiles = ProfileBook()
        entrants = [.guest]
        seatIdentities = Array(repeating: .guest, count: CouchGame.maxLocalPlayers)
        rememberedProfiles = [:]
        runRecords = .none
        // Then the disk, including every `skid.` default — which is what puts the dials,
        // the d-pad shape and the legacy custom-track slot back to their stock values.
        ResetAllData.wipe()
        // The dials are `@AppStorage`, so their in-memory copies survive the sweep;
        // this is what makes the live settings object agree with the emptied store.
        settings.resetPhysics()
        settings.pace = 1
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
