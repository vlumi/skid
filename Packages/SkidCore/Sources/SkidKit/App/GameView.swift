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
            case .setup:
                SetupView(game: game)
            case .racing:
                if let session = game.session, let rig = game.rig {
                    RaceScreen(game: game, session: session, rig: rig, net: net)
                        // **Identity, or a rematch keeps the old race's wiring.** A
                        // networked rematch replaces the session and the rig while the
                        // phase stays `.racing`, so SwiftUI reuses this view and its
                        // `@ObservedObject`s keep their ORIGINAL references — the pad
                        // on screen then drives a session nobody advances, which is
                        // exactly "the client's controls do nothing". Reported from
                        // device. A local race gets a new session too (`raceAgain`),
                        // so this is not networking-specific.
                        .id(ObjectIdentifier(session))
                }
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
    }
}
