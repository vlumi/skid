import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The list is the single source of truth, and seats derive from it.**
///
/// Written after a real bug: the picker wrote `seatIdentities` while the list read
/// `entrants`, so choosing a named player left the row showing Guest. Two parallel models
/// with no test that they agree.
@MainActor
final class PlayerListTests: XCTestCase {
    private func game() -> CouchGame {
        let unique = UUID().uuidString
        return CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-lib-\(unique).json",
            profileFilename: "test-profiles-\(unique).json")
    }

    /// **Choosing a player must change the ROW**, not just a parallel seat array.
    /// Sabotage: point `createProfile` back at `assign(toSeat:)` and this fails.
    func testCreatingAProfileChangesTheRow() throws {
        let game = self.game()
        let sam = try XCTUnwrap(game.createProfile(named: "Sam", colorIndex: 0, forSeat: 0))
        XCTAssertEqual(game.entrants[0], .profile(sam.id), "the row still shows a guest")
        XCTAssertEqual(game.entrants[0].kind, .player)
        XCTAssertEqual(game.entrantDetail(0), "Sam")
        // …and the derived seat agrees, because it comes from the row.
        XCTAssertEqual(game.identity(inSeat: 0), .profile(sam.id))
    }

    /// **AI is a race setting, not a list row.** Filling turns the empty grid into
    /// opponents; the list stays people-only. Sabotage: make `aiCount` read the list
    /// again and this stops responding to the toggle.
    func testFillingTheGridDerivesTheAICount() {
        let game = self.game()
        game.fillWithAI = true
        XCTAssertEqual(game.playerCount, 1)
        XCTAssertEqual(game.aiCount, CouchGame.maxCars - 1)

        XCTAssertTrue(game.addEntrant(.guest))
        XCTAssertEqual(game.aiCount, CouchGame.maxCars - 2, "a person did not take an AI's place")

        game.fillWithAI = false
        XCTAssertEqual(game.aiCount, 0)
    }

    /// **A nearby race never carries AI**, whatever the toggle says: the protocol has no
    /// AI seat and a shared field belongs to whoever hosts it.
    func testANearbyRaceCarriesNoAI() {
        let game = self.game()
        game.fillWithAI = true
        XCTAssertGreaterThan(game.aiCount, 0)
        game.openNetworking()
        XCTAssertEqual(game.aiCount, 0, "AI leaked into a networked field")
    }

    /// The toggle is sticky: away to AI and back returns the same person.
    func testTheToggleRemembersThePlayer() throws {
        let game = self.game()
        _ = try XCTUnwrap(game.addEntrant(.guest) ? true : nil)
        let sam = try XCTUnwrap(game.createProfile(named: "Sam", colorIndex: 0, forSeat: 1))
        game.setKind(.guest, at: 1)
        XCTAssertEqual(game.entrants[1].kind, .guest)
        let returned = game.setKind(.player, at: 1)
        XCTAssertTrue(returned, "the row had to ask again for a player it already knew")
        XCTAssertEqual(game.entrants[1], .profile(sam.id))
    }

    /// A row with no remembered player reports that it needs the picker, rather than
    /// silently doing nothing.
    func testAPlayerRowWithNobodyAsksForThePicker() {
        let game = self.game()
        XCTAssertFalse(game.setKind(.player, at: 0), "the row claimed it could self-serve")
        XCTAssertEqual(game.entrants[0].kind, .guest)
    }

    /// The player count follows the list, so it cannot contradict it.
    func testTheCountFollowsTheList() {
        let game = self.game()
        XCTAssertEqual(game.playerCount, 1)
        XCTAssertTrue(game.addEntrant(.guest))
        XCTAssertEqual(game.playerCount, 2)
        XCTAssertEqual(game.entrants.count, 2)
    }

    /// No more people than one device can seat.
    func testHumansAreCappedPerDevice() {
        let game = self.game()
        for _ in 0..<10 { _ = game.addEntrant(.guest) }
        XCTAssertEqual(game.playerCount, CouchGame.maxLocalPlayers)
        XCTAssertFalse(game.canAdd(.guest))
    }

    /// The list never empties.
    func testTheLastRowCannotBeRemoved() {
        let game = self.game()
        game.removeEntrant(at: 0)
        XCTAssertEqual(game.entrants.count, 1)
    }
}
