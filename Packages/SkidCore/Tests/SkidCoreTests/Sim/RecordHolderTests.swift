import XCTest

@testable import SkidCore

/// **Whose record is it?**
///
/// Attribution is a snapshot: the name is stored when the time is TAKEN, and nothing
/// afterwards rewrites it. These pin the edges that make that true.
final class RecordHolderTests: XCTestCase {
    /// **The name is stored with the time.**
    func testARecordRemembersWhoSetIt() {
        var book = HiscoreBook()
        XCTAssertTrue(book.recordLap(600, track: "clover", holder: "Ada"))
        XCTAssertEqual(book.best(for: "clover").lapHolder, "Ada")
    }

    /// **A guest sets a record with no name**, rather than a placeholder one. Somebody
    /// who declined to register should not be filed under an invented identity.
    func testAGuestsRecordHasNoName() {
        var book = HiscoreBook()
        XCTAssertTrue(book.recordLap(600, track: "clover"))
        XCTAssertEqual(book.best(for: "clover").bestLapTicks, 600)
        XCTAssertNil(book.best(for: "clover").lapHolder)
    }

    /// **A slower lap changes nothing** — not the time, and not whose it is. The obvious
    /// bug this guards: writing the holder outside the improvement check, so anybody who
    /// drove after Ada would take her name off her record.
    func testASlowerLapDoesNotStealTheRecord() {
        var book = HiscoreBook()
        book.recordLap(600, track: "clover", holder: "Ada")
        XCTAssertFalse(book.recordLap(700, track: "clover", holder: "Bo"))
        XCTAssertEqual(book.best(for: "clover").lapHolder, "Ada")
        XCTAssertEqual(book.best(for: "clover").bestLapTicks, 600)
    }

    /// **Beating it takes the record over**, name and all.
    func testABetterLapTakesTheRecordOver() {
        var book = HiscoreBook()
        book.recordLap(600, track: "clover", holder: "Ada")
        XCTAssertTrue(book.recordLap(500, track: "clover", holder: "Bo"))
        XCTAssertEqual(book.best(for: "clover").lapHolder, "Bo")
    }

    /// **A guest beating a named record clears the name**, rather than leaving Ada's name
    /// against a time she did not drive — the worst outcome of the two.
    func testAGuestBeatingANamedRecordClearsTheName() {
        var book = HiscoreBook()
        book.recordLap(600, track: "clover", holder: "Ada")
        XCTAssertTrue(book.recordLap(500, track: "clover"))
        XCTAssertNil(book.best(for: "clover").lapHolder)
        XCTAssertEqual(book.best(for: "clover").bestLapTicks, 500)
    }

    /// Lap and race holders are independent: they are different achievements and can
    /// belong to different people.
    func testLapAndRaceHoldersAreSeparate() {
        var book = HiscoreBook()
        book.recordLap(500, track: "clover", holder: "Ada")
        book.recordRace(
            ticks: 1800, ghost: nil, config: RaceConfig(laps: 3), track: "clover",
            holder: "Bo")
        XCTAssertEqual(book.best(for: "clover").lapHolder, "Ada")
        XCTAssertEqual(book.best(for: "clover").raceHolder, "Bo")
    }

    /// **A book written before holders existed still reads.** The fields are optional
    /// additions at the same version, so an existing player's records survive the update
    /// rather than being wiped — which a version bump would have done.
    func testAnOlderBookAtThisVersionStillDecodes() throws {
        let json = """
            {"version":\(HiscoreBook.currentVersion),\
            "tracks":{"clover":{"bestLapTicks":600,"raceTicks":1800}}}
            """
        let book = try XCTUnwrap(HiscoreBook.decode(Data(json.utf8)))
        XCTAssertEqual(book.best(for: "clover").bestLapTicks, 600)
        XCTAssertNil(book.best(for: "clover").lapHolder, "no name, rather than a wrong one")
    }

    /// The holder survives the round trip to disk.
    func testTheHolderSurvivesEncoding() throws {
        var book = HiscoreBook()
        book.recordLap(600, track: "clover", holder: "Ada")
        let back = try XCTUnwrap(HiscoreBook.decode(book.encoded()))
        XCTAssertEqual(back.best(for: "clover").lapHolder, "Ada")
    }
}
