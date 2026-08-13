import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Who is in which seat, and what happens when nobody is.**
///
/// Every test here uses its own profile file, because a fixed path is process-wide
/// state and identities would otherwise leak between methods — the same reason
/// `CouchGame` takes an injectable library filename.
@MainActor
final class SeatIdentityTests: XCTestCase {
    /// A fresh game per test, with its own on-disk profile book.
    private func game() -> CouchGame {
        let unique = UUID().uuidString
        return CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-lib-\(unique).json",
            profileFilename: "test-profiles-\(unique).json")
    }

    override func tearDown() {
        super.tearDown()
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Skid", isDirectory: true)
        for file in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] {
            if file.hasPrefix("test-profiles-") || file.hasPrefix("test-lib-") {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
        }
    }

    /// **Everybody is a guest until they say otherwise.** The app has to be fully
    /// playable before a single profile exists, which is the whole design.
    func testEverySeatStartsAsAGuest() {
        let game = self.game()
        XCTAssertTrue(game.profiles.profiles.isEmpty)
        for seat in 0..<CouchGame.maxLocalPlayers {
            XCTAssertEqual(game.identity(inSeat: seat), .guest)
            XCTAssertNil(game.profile(inSeat: seat))
            XCTAssertEqual(game.displayName(forSeat: seat), "P\(seat + 1)")
        }
    }

    /// A seat out of range answers rather than trapping — a view lays out whatever
    /// bands the rig has, and a crash is a worse answer than "nobody in particular".
    func testAnOutOfRangeSeatIsAGuestRatherThanACrash() {
        let game = self.game()
        XCTAssertEqual(game.identity(inSeat: 99), .guest)
        XCTAssertEqual(game.identity(inSeat: -1), .guest)
        game.assign(.profile(UUID()), toSeat: 99)  // must not trap
    }

    /// Creating a profile seats it, since that is invariably why somebody typed a name.
    func testCreatingAProfileSeatsIt() throws {
        let game = self.game()
        let profile = try XCTUnwrap(game.createProfile(named: "Sam", colorIndex: 2, forSeat: 1))
        XCTAssertEqual(game.identity(inSeat: 1), .profile(profile.id))
        XCTAssertEqual(game.displayName(forSeat: 1), "Sam")
        XCTAssertEqual(game.displayName(forSeat: 0), "P1", "another seat was disturbed")
    }

    /// **An unusable name leaves the seat a guest**, which is a working outcome rather
    /// than an error state to recover from.
    func testAnEmptyNameLeavesTheSeatAGuest() {
        let game = self.game()
        XCTAssertNil(game.createProfile(named: "   ", colorIndex: 0, forSeat: 0))
        XCTAssertEqual(game.identity(inSeat: 0), .guest)
        XCTAssertTrue(game.profiles.profiles.isEmpty, "a nameless profile was stored")
    }

    /// **One person cannot drive two cars.** Taking a seat releases any other seat the
    /// same profile held — without this, picking your own name in seat 2 after being in
    /// seat 1 enters you twice and files both cars' results against you.
    func testTakingASeatReleasesTheOldOne() throws {
        let game = self.game()
        let sam = try XCTUnwrap(game.createProfile(named: "Sam", colorIndex: 0, forSeat: 0))
        game.assign(.profile(sam.id), toSeat: 2)
        XCTAssertEqual(game.identity(inSeat: 2), .profile(sam.id))
        XCTAssertEqual(game.identity(inSeat: 0), .guest, "Sam is driving two cars")
    }

    /// Two different profiles may of course sit together — the exclusivity above is per
    /// person, not a claim that only one seat can be named.
    func testTwoProfilesCanShareACouch() throws {
        let game = self.game()
        let sam = try XCTUnwrap(game.createProfile(named: "Sam", colorIndex: 0, forSeat: 0))
        let ada = try XCTUnwrap(game.createProfile(named: "Ada", colorIndex: 1, forSeat: 1))
        XCTAssertEqual(game.identity(inSeat: 0), .profile(sam.id))
        XCTAssertEqual(game.identity(inSeat: 1), .profile(ada.id))
    }

    /// Vacating is assigning `.guest` — the same operation, not a separate path.
    func testASeatCanGoBackToBeingAGuest() throws {
        let game = self.game()
        _ = try XCTUnwrap(game.createProfile(named: "Sam", colorIndex: 0, forSeat: 0))
        game.assign(.guest, toSeat: 0)
        XCTAssertEqual(game.identity(inSeat: 0), .guest)
        XCTAssertEqual(game.displayName(forSeat: 0), "P1")
        XCTAssertEqual(game.profiles.profiles.count, 1, "vacating deleted the profile")
    }

    /// **Deleting a profile must empty its seat**, or the seat would point at somebody
    /// who no longer exists and `displayName` would fall back while `identity` did not.
    func testDeletingAProfileVacatesItsSeat() throws {
        let game = self.game()
        let sam = try XCTUnwrap(game.createProfile(named: "Sam", colorIndex: 0, forSeat: 3))
        game.deleteProfile(id: sam.id)
        XCTAssertEqual(game.identity(inSeat: 3), .guest)
        XCTAssertNil(game.profile(inSeat: 3))
        XCTAssertTrue(game.profiles.profiles.isEmpty)
    }

    /// Profiles survive a relaunch — the point of having them. Same filename, new
    /// instance, so this exercises the real load path rather than in-memory state.
    func testProfilesSurviveARelaunch() throws {
        let filename = "test-profiles-relaunch-\(UUID().uuidString).json"
        let first = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-lib-relaunch.json", profileFilename: filename)
        let sam = try XCTUnwrap(first.createProfile(named: "Sam", colorIndex: 4, forSeat: 0))

        let second = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-lib-relaunch.json", profileFilename: filename)
        XCTAssertEqual(second.profiles.profile(id: sam.id)?.name, "Sam")
        XCTAssertEqual(second.profiles.profile(id: sam.id)?.colorIndex, 4)
        // Seats are NOT persisted, deliberately: who is sitting where is a property of
        // this session, not of the device.
        XCTAssertEqual(second.identity(inSeat: 0), SeatIdentity.guest)
    }

    /// A rename reaches the seat's display name, since the seat holds an id rather than
    /// a copy of the name.
    func testARenameShowsUpInTheSeat() throws {
        let game = self.game()
        var sam = try XCTUnwrap(game.createProfile(named: "Sam", colorIndex: 0, forSeat: 0))
        sam.name = "Samantha"
        game.update(sam)
        XCTAssertEqual(game.displayName(forSeat: 0), "Samantha")
    }
}
