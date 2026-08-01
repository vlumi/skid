import SkidCore
import SwiftUI

public struct GameView: View {
    @StateObject private var game = CouchGame()

    public init() {}

    public var body: some View {
        ZStack {
            switch game.phase {
            case .setup:
                SetupView(game: game)
            case .racing:
                if let session = game.session, let rig = game.rig {
                    RaceScreen(game: game, session: session, rig: rig)
                }
            case .editing:
                EditorView(game: game)
            }
        }
        .statusBarHiddenIfAvailable()
        .persistentSystemOverlays(.hidden)
    }
}
