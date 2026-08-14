import XCTest

@testable import SkidCore

final class HiscoreTests: XCTestCase {
    /// A ghost with one tick of input — enough to store and read back, without the cost of
    /// driving a real lap for a test about the book rather than about replay.
    private func sampleGhost() -> LapGhost {
        LapGhost(
            start: LapGhost.Start(
                tick: 180,
                cars: [
                    LapGhost.CarPose(
                        seat: PlayerID(0), position: Vec2(10, 20), velocity: Vec2(1, 0),
                        heading: 0.5, height: 0, steerActuator: 0.25)
                ]),
            seed: 5, players: [PlayerID(0)],
            // Quantised, as a real ghost's inputs are — the packed encoding stores
            // exactly the numbers the sim stepped, so a raw fixture would not round-trip.
            inputs: [[PlayerID(0): CarInput(steer: 0.5, throttle: 1).quantised]], ticks: 1)
    }

    func testLapRecordOnlyImproves() {
        var book = HiscoreBook()
        XCTAssertTrue(book.recordLap(1200, track: "practice-loop"))
        XCTAssertFalse(book.recordLap(1300, track: "practice-loop"))
        XCTAssertTrue(book.recordLap(1100, track: "practice-loop"))
        XCTAssertEqual(book.best(for: "practice-loop").bestLapTicks, 1100)
        // Ad-hoc tracks (empty id) never record.
        XCTAssertFalse(book.recordLap(1, track: ""))
    }

    func testRaceRecordStoresTheLapGhost() {
        var book = HiscoreBook()
        let config = RaceConfig(laps: 3, countdownTicks: 180)
        XCTAssertTrue(
            book.recordRace(
                ticks: 4000, ghost: sampleGhost(), config: config, track: "practice-loop"))
        XCTAssertFalse(
            book.recordRace(
                ticks: 4100, ghost: sampleGhost(), config: config, track: "practice-loop"))
        let best = book.best(for: "practice-loop")
        XCTAssertEqual(best.raceTicks, 4000)
        XCTAssertEqual(best.lapGhost?.seed, 5)
        XCTAssertEqual(best.lapGhost?.start.cars.first?.steerActuator, 0.25)
        XCTAssertEqual(best.raceConfig, config)
    }

    /// **Beating an old record drops the whole-race recording it carried.**
    ///
    /// The point of the new format is that the big field stops being written; a record
    /// improved after an upgrade must not keep the megabyte its predecessor held. Starts
    /// from a book that HAS one, since a fresh record's field is nil either way — an
    /// assertion on a fresh book cannot fail and proves nothing.
    func testBeatingALegacyRecordDropsItsRecording() {
        var book = HiscoreBook()
        var legacy = BestRecord()
        legacy.raceTicks = 5000
        legacy.raceRecording = RaceRecording(seed: 5, players: [PlayerID(0)])
        legacy.raceConfig = RaceConfig(laps: 3)
        book.tracks["practice-loop"] = legacy
        XCTAssertNotNil(book.best(for: "practice-loop").raceRecording)

        XCTAssertTrue(
            book.recordRace(
                ticks: 4000, ghost: sampleGhost(), config: RaceConfig(laps: 3),
                track: "practice-loop"))
        XCTAssertNil(
            book.best(for: "practice-loop").raceRecording,
            "the superseded whole-race recording was kept")
        XCTAssertNotNil(book.best(for: "practice-loop").lapGhost)
    }

    /// A race with no completed lap still records the time; there is simply nothing to
    /// race against.
    func testARaceWithNoLapStillRecordsItsTime() {
        var book = HiscoreBook()
        XCTAssertTrue(
            book.recordRace(
                ticks: 4000, ghost: nil, config: RaceConfig(laps: 3), track: "practice-loop"))
        XCTAssertEqual(book.best(for: "practice-loop").raceTicks, 4000)
        XCTAssertNil(book.best(for: "practice-loop").lapGhost)
    }

    func testEncodedRoundTrip() throws {
        var book = HiscoreBook()
        book.recordLap(999, track: "practice-loop")
        book.recordRace(
            ticks: 4000, ghost: sampleGhost(),
            config: RaceConfig(laps: 3, countdownTicks: 180), track: "practice-loop")
        let data = try book.encoded()
        XCTAssertEqual(HiscoreBook.decode(data), book)
    }

    func testDecodeRejectsGarbageAndFutureVersions() throws {
        XCTAssertNil(HiscoreBook.decode(Data("not json".utf8)))
        var future = HiscoreBook()
        future.version = HiscoreBook.currentVersion + 1
        let data = try JSONEncoder().encode(future)
        XCTAssertNil(HiscoreBook.decode(data))
    }
}
