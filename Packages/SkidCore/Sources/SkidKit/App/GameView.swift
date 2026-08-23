import SkidCore
import SwiftUI

public struct GameView: View {
    @StateObject private var game = CouchGame()
    /// Created up front so the transport's delegate is live before the lobby
    /// appears — a peer that connects while the view is being built would
    /// otherwise be missed, which reads as a join that silently did nothing.
    @StateObject private var net = NetworkedGame(displayName: DeviceName.uniqueKey())

    public init() {}

    public var body: some View {
        ZStack {
            switch game.phase {
            case .menu:
                HomeView(game: game, net: net)
            case .setup:
                SetupView(game: game)
            case .racing:
                if let session = game.session, let rig = game.rig {
                    RaceScreen(game: game, session: session, rig: rig, net: net)
                        // **Identity, or a rematch keeps the old race's wiring.** A
                        // rematch replaces the session and the rig while the phase
                        // stays `.racing`, so SwiftUI reuses this view and its
                        // `@ObservedObject`s keep their ORIGINAL references — the pad
                        // on screen then drives a session nobody advances, which is
                        // exactly "the client's controls do nothing".
                        //
                        // **Keyed by the race, NOT by `ObjectIdentifier`.** An
                        // identifier is an address, and the old session is freed
                        // before the new one is allocated — so the allocator can hand
                        // back the SAME address, the id compares equal, and the view
                        // is reused after all. That is why it worked on the first
                        // rematch and failed on the second: alternating addresses.
                        // Reported from device, twice.
                        .id(session.raceKey)
                }
            case .tracks:
                // **Its own screen, one level below the front door.** Choosing a
                // track is not an interruption of editing — it is where editing
                // starts from, and where sharing one lives.
                TrackShelfView(
                    game: game,
                    back: { game.backToMenu() },
                    openCanvas: { game.openEditor() })
            case .editing:
                EditorView(game: game)
            case .networking:
                NetworkLobbyView(net: net, game: game)
            }
        }
        .onAppear {
            // The lobby hands the race over here: `NetworkedGame` knows the seed,
            // roster and course; `CouchGame` knows how to build a session from them.
            net.onStart { start in
                game.startNetworkedRace(start, driver: net)
            }
        }
        .statusBarHiddenIfAvailable()
        .persistentSystemOverlays(.hidden)
        // **Shake for the tuning dials — development builds only.** Applied at the
        // root so every phase inherits it, which is the point: the dials used to be
        // a pause-menu button, reachable only from inside a race. In a production
        // build this is the identity function.
        .tuningOnShake(settings: game.settings) { game.resetAllData() }
    }
}
