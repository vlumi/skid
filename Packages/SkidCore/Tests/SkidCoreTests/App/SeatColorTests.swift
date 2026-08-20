import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Picking a color at the couch** — the tap that cycles a seat, the profile
/// preference it remembers, and the permutation that keeps every seat distinct.
@MainActor
final class SeatColorTests: XCTestCase {
    private func game() -> CouchGame {
        CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-color-\(UUID().uuidString).json",
            profileFilename: "test-color-\(UUID().uuidString).json",
            setupFilename: "test-color-\(UUID().uuidString).json")
    }

    /// **The tap must actually change the color.** The slots array covers the
    /// whole grid and defaults to all nine palette colors, so counting every
    /// slot as taken left exactly one "free" color — the tapper's own — and the
    /// shipped button cycled in place. Reported as friction.
    func testCyclingActuallyChangesTheColor() {
        let couch = game()
        let before = couch.colorIndices[0]
        couch.cycleColor(slot: 0)
        XCTAssertNotEqual(couch.colorIndices[0], before, "the color button is a no-op")
    }

    /// Another RACING seat's color is skipped; an idle slot's is fair game.
    func testCyclingSkipsOnlyTheRacingSeatsColors() {
        let couch = game()
        couch.addEntrant(.guest)  // two players racing
        let neighbor = couch.colorIndices[1]
        for _ in 0..<(CarPalette.count * 2) {
            couch.cycleColor(slot: 0)
            XCTAssertNotEqual(
                couch.colorIndices[0], couch.colorIndices[1],
                "a cycle landed on the other racing seat's color")
        }
        XCTAssertEqual(couch.colorIndices[1], neighbor, "cycling seat 0 moved seat 1")
    }

    /// The slots stay a permutation of the palette — the pickers swap rather
    /// than overwrite, so a player added later can never arrive color-twinned.
    func testTheSlotsStayAPermutation() {
        let couch = game()
        couch.addEntrant(.guest)
        for _ in 0..<5 { couch.cycleColor(slot: 0) }
        couch.cycleColor(slot: 1)
        XCTAssertEqual(
            Set(couch.colorIndices), Set(0..<CarPalette.count),
            "a pick broke the permutation: \(couch.colorIndices)")
    }

    /// A profile placed in a seat brings its preferred color along.
    func testAProfileSeedsItsPreferredColor() {
        let couch = game()
        let profile = couch.createProfile(named: "Sam", colorIndex: 7, forSeat: 0)
        XCTAssertNotNil(profile)
        XCTAssertEqual(couch.colorIndices[0], 7, "the preference did not reach the seat")
        XCTAssertEqual(Set(couch.colorIndices), Set(0..<CarPalette.count))
    }

    /// Two profiles wanting the same color: the seat filled first keeps it —
    /// the same first-come rule the networked roster applies.
    func testASeatedPreferenceHoldsAgainstALaterOne() {
        let couch = game()
        _ = couch.createProfile(named: "Sam", colorIndex: 7, forSeat: 0)
        couch.addEntrant(.guest)
        _ = couch.createProfile(named: "Alex", colorIndex: 7, forSeat: 1)
        XCTAssertEqual(couch.colorIndices[0], 7, "the earlier claim was disturbed")
        XCTAssertNotEqual(couch.colorIndices[1], 7, "two seats share a color")
    }

    /// An explicit pick becomes the profile's preference; a bump at seeding
    /// time must NOT — one crowded race is not a change of heart.
    func testCyclingUpdatesThePreferenceButSeedingNever() throws {
        let couch = game()
        let sam = try XCTUnwrap(couch.createProfile(named: "Sam", colorIndex: 7, forSeat: 0))
        couch.cycleColor(slot: 0)
        let picked = couch.colorIndices[0]
        XCTAssertEqual(
            couch.profiles.profile(id: sam.id)?.colorIndex, picked,
            "an explicit pick must be remembered on the profile")

        // Alex prefers the same color Sam now holds; seeding bumps the SEAT
        // but must leave Alex's stored preference alone.
        couch.addEntrant(.guest)
        let alex = try XCTUnwrap(
            couch.createProfile(named: "Alex", colorIndex: picked, forSeat: 1))
        XCTAssertNotEqual(couch.colorIndices[1], picked)
        XCTAssertEqual(
            couch.profiles.profile(id: alex.id)?.colorIndex, picked,
            "a seeding bump overwrote the player's stated preference")
    }

    /// The picks survive a relaunch, exactly like the rest of the setup.
    func testColorsSurviveARelaunch() {
        let filename = "test-color-\(UUID().uuidString).json"
        let before = CouchGame(signingKeys: NoSigningKey(), setupFilename: filename)
        before.cycleColor(slot: 0)
        let picked = before.colorIndices
        let after = CouchGame(signingKeys: NoSigningKey(), setupFilename: filename)
        XCTAssertEqual(after.colorIndices, picked)
    }

    /// A remembered file with a broken color list (duplicates — hand-edited or
    /// from a future palette) is ignored rather than half-applied: the pickers
    /// all assume no two slots are alike.
    func testABrokenRememberedColorListIsIgnored() {
        let filename = "test-color-\(UUID().uuidString).json"
        var memory = SetupMemory(
            mode: .race, trackID: TrackLibrary.builtins[0].id,
            entrants: [.guest], schemes: [.casual, .casual, .casual, .casual],
            fillWithAI: true, aiDifficulty: .medium)
        memory.colorIndices = Array(repeating: 3, count: PieceCompiler.Grid.slots)
        SetupFile(filename: filename).save(memory)
        let after = CouchGame(signingKeys: NoSigningKey(), setupFilename: filename)
        XCTAssertEqual(after.colorIndices, Array(0..<PieceCompiler.Grid.slots))
    }
}
