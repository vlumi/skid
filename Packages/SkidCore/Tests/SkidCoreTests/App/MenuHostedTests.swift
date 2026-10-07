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

    /// **The window follows the game.** `GameView` switches screens on
    /// `phase` alone, so this is the observation the whole app hangs off: if
    /// the view stopped tracking it, a press would change the phase and leave
    /// the old screen up. Race setup has a Back corner; the front door has none.
    func testTheWindowFollowsThePhase() throws {
        let couch = game()
        let window = host(GameView(game: couch, net: NetworkedGame(displayName: "t")))
        defer { window.close() }
        let scope = try XCTUnwrap(couch.menus.active, "the window pushed no scope")
        XCTAssertFalse(scope.targets.isEmpty, "the front door's buttons did not register")
        XCTAssertFalse(scope.targets.contains(where: \.isCancel), "the front door has a Back")
        couch.openSetup()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(
            scope.targets.contains(where: \.isCancel), "the phase changed but the screen did not")
        couch.backToMenu()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(
            scope.targets.contains(where: \.isCancel), "back on the front door, setup is still up")
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

    /// **A sheet takes the keys while it is up.** The focus centre has to
    /// reach the sheet's content through the environment; if it did not, the
    /// sheet would push no scope and the arrows would move the screen behind.
    func testASheetPushesItsOwnScope() throws {
        let couch = game()
        let center = couch.menus
        struct Probe: View {
            @State var showing = true
            var body: some View {
                MenuButton(action: {}) { Text(verbatim: "screen") }
                    .sheet(isPresented: $showing) {
                        AboutView(close: { showing = false })
                    }
            }
        }
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: Probe().menuFocusScope().menuFocusCenter(center))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        // The sheet's scope holds the sheet's buttons ONLY — About has just its
        // ×. If the sheet pushed no scope of its own, its buttons would have
        // joined the SCREEN's scope through the environment, and the active
        // scope would also hold the screen's button behind it.
        let active = try XCTUnwrap(center.active, "no scope at all")
        XCTAssertFalse(active.targets.isEmpty, "the sheet's buttons did not register")
        XCTAssertTrue(
            active.targets.allSatisfy(\.isCancel),
            "the arrows would reach the screen behind the sheet: "
                + "\(active.targets.count) targets, not just the sheet's close")
    }
}
#endif
