import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// **Shake the device to open the tuning panel — in development builds only.**
///
/// The tuning dials are a developer tool: 25 of the app's 28 persisted settings are
/// `skid.sim.*`, `skid.aim.*` and friends, and they exist for on-device A/B tests
/// rather than for players. They used to hang off a **Tuning** button in the pause
/// menu, which had two problems: it put a developer control in the player's way, and
/// it was only reachable *during a race* — so tuning anything about the menus, the
/// editor or the lobby meant starting a race first.
///
/// A shake fixes both. It is reachable from anywhere, and it occupies no pixels, so
/// the menus can be designed as if the panel did not exist.
///
/// **And in a production build it does not exist.** Everything here is behind
/// `SKID_EXPERIMENTAL`, so the release binary contains no gesture hook, no panel
/// presentation and no way in — which is stronger than hiding a button, and is the
/// point: a hidden control still ships. See `docs/experimental-features.md`.
enum ShakeToTune {
    /// Posted when the device is shaken. Named rather than a closure so the detector
    /// (a `UIWindow` subclass, which SwiftUI does not own) can reach the view layer
    /// without either side holding the other.
    static let shaken = Notification.Name("fi.misaki.skid.deviceShaken")
}

#if SKID_EXPERIMENTAL && canImport(UIKit)

/// Turns the system's built-in shake detection into a notification.
///
/// `motionEnded` is UIKit's own shake recognizer — the same hook the standard
/// shake-to-undo uses — so this needs no accelerometer polling, no thresholds to
/// tune, and no CoreMotion. It also means the gesture feels exactly like every other
/// iOS shake, because it *is* that gesture.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        NotificationCenter.default.post(name: ShakeToTune.shaken, object: nil)
    }
}

#endif

extension View {
    /// Present the tuning panel on a shake, over whatever is on screen.
    ///
    /// Applied once at the app's root, so every screen inherits it — the race, the
    /// menus, the editor, the lobby. In a production build this is the identity
    /// function: no listener, no sheet, nothing retained.
    func tuningOnShake(settings: GameSettings) -> some View {
        #if SKID_EXPERIMENTAL && canImport(UIKit)
        return modifier(ShakeTuningModifier(settings: settings))
        #else
        return self
        #endif
    }
}

#if SKID_EXPERIMENTAL && canImport(UIKit)

private struct ShakeTuningModifier: ViewModifier {
    @ObservedObject var settings: GameSettings
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: ShakeToTune.shaken)) { _ in
                // Toggle rather than set: a second shake closes it, so the panel can
                // be dismissed the same way it was opened even if its own close
                // button is somehow off-screen.
                showing.toggle()
            }
            .sheet(isPresented: $showing) {
                // A sheet rather than an overlay, deliberately: it dims and blocks
                // what is underneath, so a stray drag while a slider is open cannot
                // reach the controls of a live race behind it.
                TuningPanel(settings: settings) { showing = false }
            }
    }
}

#endif
