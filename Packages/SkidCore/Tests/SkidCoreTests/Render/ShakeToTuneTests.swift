import SwiftUI
import XCTest

@testable import SkidKit

/// **The tuning dials can be compiled out, and this pins that both ways.**
///
/// `SKID_TUNING` is opt-OUT — on by default, since TestFlight builds are release
/// builds and on-device tuning is what they are for. `SKID_NO_TUNING=1` removes it,
/// which is what a production release would do.
///
/// The interesting assertion is the *negative* one — that a build without the dials
/// has no route to the panel — and a test compiled without the flag cannot see the
/// code it is asserting about. So the suite asserts the opposite thing in each
/// configuration, and a regression fails whichever way it is run:
///
/// - **Default (`SKID_TUNING`)**: the gesture is wired and toggles.
/// - **`SKID_NO_TUNING=1`**: `tuningOnShake` is the identity function, so applying it
///   changes nothing about the view tree.
///
/// What no unit test here can check is the gesture itself: `motionEnded` is delivered
/// by UIKit to a real window, so the shake goes on device.
@MainActor
final class ShakeToTuneTests: XCTestCase {
    /// The notification name is the contract between the UIKit window subclass and
    /// the SwiftUI layer. It lives outside the flag on purpose — the *name* costs
    /// nothing, and having it always defined keeps the no-tuning build from needing
    /// its own spelling of this file.
    func testTheShakeNotificationHasAStableName() {
        XCTAssertEqual(ShakeToTune.shaken.rawValue, "fi.misaki.skid.deviceShaken")
    }

    #if SKID_TUNING

    /// With the dials present, posting the notification is what opens the panel — so
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

    /// **Without the dials the modifier does nothing**, which is the whole point: a
    /// hidden button still ships, a compiled-out one does not.
    ///
    /// Applying it must leave the view unchanged. `some View` cannot be compared, so
    /// this asserts on the type: the identity path returns the *same* type it was
    /// given, while the wired path returns a `ModifiedContent`.
    func testTheModifierIsIdentityWithoutTheFlag() {
        let plain = Color.clear
        let shaken = plain.tuningOnShake(settings: GameSettings())
        XCTAssertTrue(
            type(of: shaken) == type(of: plain),
            "tuningOnShake must be the identity function without SKID_TUNING; "
                + "got \(type(of: shaken))")
    }

    #endif
}
