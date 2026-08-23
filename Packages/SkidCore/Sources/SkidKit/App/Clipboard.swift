import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// **The clipboard, in one place.**
///
/// Every copy/paste path used to spell out its own `#if canImport(UIKit)` around
/// `UIPasteboard`, which is three lines of platform noise per call site and a
/// silent no-op on the Mac test target — where the paste paths are exactly the
/// ones worth testing. One seam instead, with an injectable override so a test
/// can put something on the "clipboard" without touching the real one.
@MainActor
public enum Clipboard {
    /// What a test says the clipboard holds. Nil means use the real one.
    ///
    /// Deliberately not a protocol and an injected instance: this is read from
    /// SwiftUI button actions all over the app, and threading a dependency
    /// through every view to test two paste paths would cost more than it buys.
    static var testOverride: String??

    public static func copy(_ text: String) {
        if testOverride != nil {
            testOverride = .some(text)
            return
        }
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    public static func paste() -> String? {
        if let override = testOverride { return override }
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #else
        return nil
        #endif
    }
}
