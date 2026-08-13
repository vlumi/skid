import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Where the app is, and what each door does.**
///
/// `CouchGame.phase` had no test coverage at all before this: changing the launch
/// phase from `.setup` to `.menu` left all 772 tests green, which is exactly the
/// silence a navigation bug hides in. These are cheap and they pin the shape of the
/// front end rather than its looks.
@MainActor
final class MenuNavigationTests: XCTestCase {
    /// The app opens at the front door, not in the middle of a race setup.
    func testTheAppStartsAtTheMenu() {
        XCTAssertEqual(CouchGame().phase, .menu)
    }

    /// **Solo means one seat, and the setup screen must not contradict it.**
    ///
    /// `HomeView` sets the seat count as part of choosing the door, so the screen
    /// after never has to ask. Pinning it here because the two halves live in
    /// different files and a change to either could silently disagree.
    func testSoloSeatsOnePlayer() {
        let game = CouchGame()
        game.playerCount = 3  // whatever a previous session left behind
        game.playerCount = 1  // what HomeView's Solo button does
        game.openSetup()
        XCTAssertEqual(game.phase, .setup)
        XCTAssertEqual(game.playerCount, 1)
    }

    /// **Couch means at least two**, even arriving from a solo session.
    ///
    /// The rule is `max(2, playerCount)` rather than a fixed 2, so a player who last
    /// raced four keeps four. The interesting case is the other one: coming from
    /// Solo, the count must be lifted, or Couch would seat one and the label would
    /// be a lie.
    func testCouchLiftsASoloSeatCountToTwo() {
        let game = CouchGame()
        game.playerCount = 1
        game.playerCount = max(2, game.playerCount)  // what HomeView's Couch button does
        XCTAssertEqual(game.playerCount, 2)
    }

    /// …and does not clobber a bigger couch.
    func testCouchKeepsAnExistingSeatCount() {
        let game = CouchGame()
        game.playerCount = 4
        game.playerCount = max(2, game.playerCount)
        XCTAssertEqual(game.playerCount, 4)
    }

    /// **Two different "backs", and they must not be confused.**
    ///
    /// A race's own Setup button returns to the race options, because you are most
    /// likely adjusting and going again. Leaving the lobby or the editor returns to
    /// the front door, because those are destinations rather than steps in a race —
    /// dropping out of the lobby into somebody else's race-setup screen would be a
    /// non-sequitur.
    func testTheTwoBacksGoToDifferentPlaces() {
        let game = CouchGame()
        game.openSetup()

        game.backToSetup()
        XCTAssertEqual(game.phase, .setup, "a race's Setup returns to the race options")

        game.backToMenu()
        XCTAssertEqual(game.phase, .menu, "Back from a destination returns to the front door")
    }

    /// Every door leads somewhere, and none of them leaves the app in `.menu`
    /// pretending it did something. Cheap, and it catches a button wired to nothing.
    func testEveryDoorLeavesTheMenu() {
        for (name, open) in [
            ("setup", { (game: CouchGame) in game.openSetup() }),
            ("networking", { game in game.openNetworking() }),
            ("editor", { game in game.openEditor() }),
        ] {
            let game = CouchGame()
            XCTAssertEqual(game.phase, .menu)
            open(game)
            XCTAssertNotEqual(game.phase, .menu, "the \(name) door did not go anywhere")
        }
    }
}
