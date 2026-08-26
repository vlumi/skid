import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// **Shake the device to open the tuning panel.**
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
/// **Behind `SKID_TUNING`, which is opt-OUT — on unless explicitly removed.**
/// Deliberately the opposite default from `SKID_EXPERIMENTAL`, and a separate flag
/// from it, because the two are wanted in different places: **TestFlight builds are
/// release builds**, and tuning on a real device is what they are for, so gating
/// these as "experimental" would remove them from exactly the builds that need them.
/// One flag per feature, rather than one flag meaning "unfinished".
///
/// Building with `SKID_NO_TUNING=1` removes it: no gesture hook, no panel
/// presentation, no way in. That is stronger than hiding a button, which is the
/// point — a hidden control still ships. See `docs/experimental-features.md`.
enum ShakeToTune {
    /// Posted when the device is shaken. Named rather than a closure so the detector
    /// (a `UIWindow` subclass, which SwiftUI does not own) can reach the view layer
    /// without either side holding the other.
    static let shaken = Notification.Name("fi.misaki.skid.deviceShaken")
}

#if SKID_TUNING && canImport(UIKit)

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
    /// menus, the editor, the lobby. Built with `SKID_NO_TUNING=1` this is the
    /// identity function: no listener, no sheet, nothing retained.
    /// `resetAllData` adds the panel's wipe-everything button; omit it and the button
    /// is absent, which is how a caller without a game to reset stays valid.
    func tuningOnShake(
        settings: GameSettings, resetAllData: (() -> Void)? = nil
    ) -> some View {
        #if SKID_TUNING && canImport(UIKit)
        return modifier(ShakeTuningModifier(settings: settings, resetAllData: resetAllData))
        #else
        return self
        #endif
    }
}

#if SKID_TUNING && canImport(UIKit)

private struct ShakeTuningModifier: ViewModifier {
    @ObservedObject var settings: GameSettings
    let resetAllData: (() -> Void)?
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                // `simctl` cannot shake a simulator, so a panel reached only by shaking
                // is otherwise unreachable for a screenshot.
                if LaunchFlag.consume("-skid-tuning") {
                    showing = true
                }
            }
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
                TuningPanel(
                    settings: settings, close: { showing = false },
                    resetAllData: resetAllData)
            }
    }
}

#endif
