#if os(macOS)
import AppKit
import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The real screens, hosted**: their buttons register with the keyboard
/// focus, and keys pressed through the game move between them and press them.
@MainActor
final class MenuHostedTests: XCTestCase {
    private func host(_ view: some View, size: CGSize = CGSize(width: 900, height: 900)) -> NSWindow
    {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
            backing: .buffered, defer: false)
        // The test owns it: closing must not also free it (the default for a
        // window made in code), or the test's own reference dangles.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: view.frame(width: size.width, height: size.height))
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return window
    }

    private func game() -> CouchGame {
        CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "hosted-\(UUID().uuidString).json",
            profileFilename: "hosted-\(UUID().uuidString).json",
            setupFilename: "hosted-\(UUID().uuidString).json")
    }

    /// **The front door by keys alone**: down from nothing lands on the first
    /// button, the highlight walks the real layout, and Enter on START opens
    /// race setup — the same button a tap would press.
    func testTheFrontDoorByKeys() throws {
        let couch = game()
        couch.keyboardDriving = true
        let window = host(
            HomeView(game: couch, net: NetworkedGame(displayName: "t"))
                .menuFocusScope().menuFocusCenter(couch.menus))
        defer { window.close() }
        let scope = try XCTUnwrap(couch.menus.active, "the screen pushed no scope")
        XCTAssertGreaterThanOrEqual(
            scope.targets.count, 8, "the home screen's buttons did not register")
        XCTAssertTrue(scope.targets.allSatisfy { $0.frame.width > 0 }, "a button has no frame")
        // Down until the highlight reaches the widest button — START.
        var steps = 0
        repeat {
            couch.handle(.drive(.down, down: true))
            couch.handle(.drive(.down, down: false))
            steps += 1
        } while (scope.focused?.frame.height ?? 0) < 60 && steps < 8
        XCTAssertLessThan(steps, 8, "never reached START by arrows")
        couch.handle(.start)
        XCTAssertEqual(couch.phase, .setup, "Enter on START did not open race setup")
    }

    /// **Escape takes the corner way out**: on race setup it goes back.
    func testEscapeGoesBackFromSetup() throws {
        let couch = game()
        couch.keyboardDriving = true
        couch.openSetup()
        let window = host(SetupView(game: couch).menuFocusScope().menuFocusCenter(couch.menus))
        defer { window.close() }
        XCTAssertNotNil(couch.menus.active)
        couch.handle(.pause)
        XCTAssertEqual(couch.phase, .menu, "Escape did not press Back")
    }
}
#endif
