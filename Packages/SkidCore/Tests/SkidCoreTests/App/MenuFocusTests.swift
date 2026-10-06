import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Menus by keyboard**: arrows move a highlight between a surface's buttons,
/// Enter presses it, Escape takes the surface's way out — and the same keys
/// still drive once a race is under way.
@MainActor
final class MenuFocusTests: XCTestCase {
    /// A surface of three buttons in a row and a corner "back", each counting
    /// its presses.
    @MainActor
    private final class Surface {
        let scope = MenuFocusScope()
        var presses: [String: Int] = [:]
        var targets: [String: MenuTarget] = [:]

        init() {
            add("back", CGRect(x: 0, y: 0, width: 44, height: 44), cancel: true)
            for (i, name) in ["a", "b", "c"].enumerated() {
                add(name, CGRect(x: Double(i) * 120, y: 100, width: 100, height: 40))
            }
        }

        private func add(_ name: String, _ frame: CGRect, cancel: Bool = false) {
            let target = MenuTarget()
            target.frame = frame
            target.isCancel = cancel
            target.action = { [unowned self] in presses[name, default: 0] += 1 }
            targets[name] = target
            scope.register(target)
        }

        var focusedName: String? {
            targets.first { $0.value === scope.focused }?.key
        }
    }

    func testArrowsMoveEnterPressesEscapeLeaves() {
        let surface = Surface()
        surface.scope.move(.down)
        XCTAssertEqual(
            surface.focusedName, "back", "the first press should land reading-order first")
        surface.scope.move(.down)
        XCTAssertEqual(surface.focusedName, "a")
        surface.scope.move(.right)
        surface.scope.move(.right)
        XCTAssertEqual(surface.focusedName, "c")
        surface.scope.activate()
        XCTAssertEqual(surface.presses["c"], 1)
        surface.scope.cancel()
        XCTAssertEqual(surface.presses["back"], 1, "Escape did not take the way out")
    }

    /// Enter with nothing highlighted shows the highlight rather than pressing
    /// a button the player never chose.
    func testEnterWithNothingFocusedOnlyShowsTheHighlight() {
        let surface = Surface()
        surface.scope.activate()
        XCTAssertNotNil(surface.scope.focused)
        XCTAssertTrue(surface.presses.isEmpty, "Enter pressed a button nobody picked")
    }

    /// A button that goes away takes the highlight with it.
    func testUnregisteringTheFocusedButtonClearsTheFocus() {
        let surface = Surface()
        surface.scope.move(.down)
        surface.scope.unregister(surface.scope.focused!)
        XCTAssertNil(surface.scope.focused)
    }

    /// A sheet's surface takes the keys while it is up, and gives them back.
    func testTheTopSurfaceTakesTheKeys() {
        let center = MenuFocusCenter()
        let screen = MenuFocusScope(), sheet = MenuFocusScope()
        center.push(screen)
        center.push(sheet)
        XCTAssertTrue(center.active === sheet)
        center.pop(sheet)
        XCTAssertTrue(center.active === screen)
    }

    // MARK: - Through the game

    private func game() -> CouchGame {
        let couch = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "menu-\(UUID().uuidString).json",
            profileFilename: "menu-\(UUID().uuidString).json",
            setupFilename: "menu-\(UUID().uuidString).json")
        couch.keyboardDriving = true
        couch.fillWithAI = false
        couch.trackID = "oval"
        return couch
    }

    /// **In a menu the arrows navigate** — and do not quietly hold a driving
    /// key down for the next race.
    func testInAMenuTheKeysNavigate() {
        let couch = game()
        let surface = Surface()
        couch.menus.push(surface.scope)
        XCTAssertTrue(couch.handle(.drive(.right, down: true)))
        XCTAssertNotNil(surface.scope.focused, "the arrow did not move the highlight")
        XCTAssertTrue(couch.keyboard.seats.allSatisfy { $0.held.isEmpty }, "a menu arrow was held")
        XCTAssertTrue(couch.handle(.drive(.s, down: true)), "WASD should navigate too")
        couch.handle(.start)
        XCTAssertEqual(surface.presses.values.reduce(0, +), 1, "Enter did not press")
        couch.handle(.pause)
        XCTAssertEqual(surface.presses["back"], 1, "Escape did not go back")
    }

    /// **The same keys drive once the race is under way**, navigate the pause
    /// menu while paused, and Escape closes it.
    func testDuringARaceTheKeysDriveAndPausedTheyNavigate() throws {
        let couch = game()
        couch.mode = .race
        couch.startRace()
        let session = try XCTUnwrap(couch.session)
        couch.handle(.start)
        let pauseMenu = Surface()
        couch.menus.push(pauseMenu.scope)

        couch.handle(.drive(.up, down: true))
        XCTAssertTrue(couch.keyboard.seats[0].held.contains(.up), "racing: ↑ did not drive")
        XCTAssertNil(pauseMenu.scope.focused, "racing: ↑ moved a menu highlight")
        couch.handle(.drive(.up, down: false))

        couch.handle(.pause)
        XCTAssertTrue(session.paused)
        couch.handle(.drive(.right, down: true))
        XCTAssertNotNil(pauseMenu.scope.focused, "paused: → did not move the highlight")
        XCTAssertFalse(couch.keyboard.seats[0].held.contains(.right), "paused: → was held")
        couch.handle(.pause)
        XCTAssertFalse(session.paused, "Escape did not close the pause menu")
    }
}
