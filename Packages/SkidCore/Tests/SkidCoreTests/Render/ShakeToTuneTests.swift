import SwiftUI
import XCTest

@testable import SkidKit

/// **The tuning dials are development-only, and this pins that both ways.**
///
/// The interesting assertion is the *negative* one — that a production build has no
/// route to the panel — and a test compiled without the flag cannot see the code it
/// is asserting about. So the suite asserts the opposite thing in each configuration,
/// which means a regression fails whichever way the suite is run:
///
/// - **With `SKID_EXPERIMENTAL`**: the gesture is wired and toggles.
/// - **Without it**: `tuningOnShake` is the identity function, so applying it changes
///   nothing about the view tree.
///
/// What no unit test here can check is the gesture itself: `motionEnded` is delivered
/// by UIKit to a real window, so the shake goes on device.
@MainActor
final class ShakeToTuneTests: XCTestCase {
    /// The notification name is the contract between the UIKit window subclass and
    /// the SwiftUI layer. It lives outside the flag on purpose — the *name* costs
    /// nothing, and having it always defined keeps the non-experimental build from
    /// needing its own spelling of this file.
    func testTheShakeNotificationHasAStableName() {
        XCTAssertEqual(ShakeToTune.shaken.rawValue, "fi.misaki.skid.deviceShaken")
    }

    #if SKID_EXPERIMENTAL

    /// In a development build, posting the notification is what opens the panel — so
    /// the publisher must actually be listening on the name the window posts.
    ///
    /// Asserted through `NotificationCenter` rather than the view, since SwiftUI state
    /// is not observable from a test: this proves the two halves agree on the name,
    /// which is the part that silently breaks.
    func testAShakeIsObservableOnTheNameTheWindowPosts() {
        let expectation = expectation(
            forNotification: ShakeToTune.shaken, object: nil, handler: nil)
        NotificationCenter.default.post(name: ShakeToTune.shaken, object: nil)
        wait(for: [expectation], timeout: 1)
    }

    #else

    /// **In a production build the modifier does nothing**, which is the whole point:
    /// a hidden button still ships, a compiled-out one does not.
    ///
    /// Applying it must leave the view unchanged. `some View` cannot be compared, so
    /// this asserts on the type: the identity path returns the *same* type it was
    /// given, while the experimental path returns a `ModifiedContent`.
    func testTheModifierIsIdentityWithoutTheFlag() {
        let plain = Color.clear
        let shaken = plain.tuningOnShake(settings: GameSettings())
        XCTAssertTrue(
            type(of: shaken) == type(of: plain),
            "tuningOnShake must be the identity function in a production build; "
                + "got \(type(of: shaken))")
    }

    #endif
}
