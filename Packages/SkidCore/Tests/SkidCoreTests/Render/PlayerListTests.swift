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

    /// **The first row cannot be AI.** An AI-only field is a race you watch rather than
    /// one you drive — and the list would have inserted a guest to fix it, which read as
    /// "tapping AI on the first row adds a row".
    func testTheFirstRowRefusesAI() {
        let game = self.game()
        XCTAssertEqual(game.entrants.count, 1)
        game.setKind(.ai, at: 0)
        XCTAssertEqual(game.entrants[0].kind, .guest, "the first row became AI")
        XCTAssertEqual(game.entrants.count, 1, "refusing AI added a row instead")
    }

    /// A later row may be AI, which is the whole point of the option.
    func testALaterRowMayBeAI() {
        let game = self.game()
        XCTAssertTrue(game.addEntrant(.guest))
        game.setKind(.ai, at: 1)
        XCTAssertEqual(game.entrants[1].kind, .ai)
        XCTAssertEqual(game.aiCount, 1)
        XCTAssertEqual(game.playerCount, 1)
    }

    /// The toggle is sticky: away to AI and back returns the same person.
    func testTheToggleRemembersThePlayer() throws {
        let game = self.game()
        _ = try XCTUnwrap(game.addEntrant(.guest) ? true : nil)
        let sam = try XCTUnwrap(game.createProfile(named: "Sam", colorIndex: 0, forSeat: 1))
        game.setKind(.ai, at: 1)
        XCTAssertEqual(game.entrants[1].kind, .ai)
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

    /// Counts are derived, so they cannot contradict the list.
    func testCountsFollowTheList() {
        let game = self.game()
        XCTAssertEqual(game.playerCount, 1)
        XCTAssertEqual(game.aiCount, 0)
        XCTAssertTrue(game.addEntrant(.guest))
        XCTAssertTrue(game.addEntrant(.ai(.medium)))
        XCTAssertEqual(game.playerCount, 2)
        XCTAssertEqual(game.aiCount, 1)
        XCTAssertEqual(game.entrants.count, 3)
    }

    /// Humans stay ahead of AI, or somebody gets no control band.
    func testHumansStayAheadOfAI() {
        let game = self.game()
        XCTAssertTrue(game.addEntrant(.ai(.medium)))
        XCTAssertTrue(game.addEntrant(.guest))
        XCTAssertTrue(game.entrants[0].isHuman)
        XCTAssertTrue(game.entrants[1].isHuman)
        XCTAssertFalse(game.entrants[2].isHuman, "an AI is sitting where a person should be")
    }

    /// The field cannot exceed what the grid holds.
    func testTheFieldIsCapped() {
        let game = self.game()
        for _ in 0..<10 { _ = game.addEntrant(.ai(.medium)) }
        XCTAssertEqual(game.entrants.count, CouchGame.maxCars)
        XCTAssertFalse(game.canAdd(.ai))
    }

    /// …and no more people than one device can seat.
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
