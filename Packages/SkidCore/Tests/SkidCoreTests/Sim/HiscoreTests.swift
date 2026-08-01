import XCTest

@testable import SkidCore

final class HiscoreTests: XCTestCase {
    private func sampleRecording() -> RaceRecording {
        var recording = RaceRecording(seed: 5, players: [PlayerID(0)])
        recording.append([PlayerID(0): CarInput(steer: 0.5, throttle: 1)])
        return recording
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

    func testRaceRecordStoresGhostRun() {
        var book = HiscoreBook()
        let config = RaceConfig(laps: 3, countdownTicks: 180)
        XCTAssertTrue(
            book.recordRace(
                ticks: 4000, recording: sampleRecording(), config: config,
                track: "practice-loop"))
        XCTAssertFalse(
            book.recordRace(
                ticks: 4100, recording: sampleRecording(), config: config,
                track: "practice-loop"))
        let best = book.best(for: "practice-loop")
        XCTAssertEqual(best.raceTicks, 4000)
        XCTAssertEqual(best.raceRecording?.seed, 5)
        XCTAssertEqual(best.raceConfig, config)
    }

    func testEncodedRoundTrip() throws {
        var book = HiscoreBook()
        book.recordLap(999, track: "practice-loop")
        book.recordRace(
            ticks: 4000, recording: sampleRecording(),
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
