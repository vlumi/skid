import SkidKit
import SwiftUI

@main
struct SkidApp: App {
    var body: some Scene {
        // **One window, not a WindowGroup.** Every window would build its own
        // game and install its own key monitor, and each key press would then
        // drive twice — so there is no ⌘N to open a second one.
        Window("Skid Jam", id: "game") {
            GameView()
                .frame(minWidth: 900, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            SkidMacCommands()
        }
    }
}
