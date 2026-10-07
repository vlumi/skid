import SkidCore
import SwiftUI

public struct GameView: View {
    @State private var games = BuiltOnce { CouchGame() }
    /// Created up front so the transport's delegate is live before the lobby
    /// appears — a peer that connects while the view is being built would
    /// otherwise be missed, which reads as a join that silently did nothing.
    @State private var nets = BuiltOnce { NetworkedGame(displayName: DeviceName.uniqueKey()) }

    private var game: CouchGame { games.value }
    private var net: NetworkedGame { nets.value }

    public init() {}

    /// A window over games the caller owns — the hosted tests' way in.
    init(game: CouchGame, net: NetworkedGame) {
        _games = State(initialValue: BuiltOnce { game })
        _nets = State(initialValue: BuiltOnce { net })
    }

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
                        // stays `.racing`, so SwiftUI reuses this view and what it
                        // holds across updates keeps its ORIGINAL references — the pad
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
        // **A tapped link.** The whole track is in the URL, so this needs no
        // network and works offline — see `TrackLink`. It offers rather than
        // files: `receive` parks the track and shows the library, where the
        // sheet below asks.
        .onOpenURL { url in
            _ = game.receive(url: url)
        }
        .sheet(
            isPresented: Binding(
                get: { game.incomingTrack != nil },
                set: { if !$0 { game.declineIncomingTrack() } })
        ) {
            if let incoming = game.incomingTrack {
                IncomingTrackSheet(game: game, incoming: incoming) {
                    game.declineIncomingTrack()
                }
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
        // **Keyboard focus**: one scope for the window's screens (a phase
        // change swaps their buttons in and out of it), and every sheet pushes
        // its own over it.
        .menuFocusScope()
        .menuFocusCenter(game.menus)
        .retroButtonsOnMac()
        .tuningOnShake(settings: game.settings, keyboardDriving: game.keyboardDriving) {
            game.resetAllData()
        }
        #if os(macOS)
        // The Mac drives with keys. Only the Mac shell hosts this view on
        // macOS — the test suite, which also runs there, never builds it.
        .keyboardDriving(game)
        #endif
    }
}

/// **Built once per view identity, as `@StateObject` did.** `@State` keeps only
/// the first instance it is given, but evaluates its initial value on EVERY
/// init of the view — and `CouchGame.init` writes the library file and
/// consumes launch flags, so a discarded copy is not free. The box is what
/// gets thrown away; what it builds is built on first read, from the kept box.
@MainActor
final class BuiltOnce<Value: AnyObject> {
    private let make: () -> Value
    private(set) lazy var value = make()

    init(_ make: @escaping () -> Value) { self.make = make }
}
