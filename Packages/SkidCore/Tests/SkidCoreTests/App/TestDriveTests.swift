import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Watching the AI drive what you are building, and getting back.**
///
/// The round trip is where the bugs are: a test drive that leaves the game in
/// `.race` on a throwaway track, or files a record against it, or loses the
/// layout, is worse than no test drive at all.
@MainActor
final class TestDriveTests: XCTestCase {
    private func game() -> CouchGame {
        CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-drive-\(UUID().uuidString).json",
            profileFilename: "test-drive-\(UUID().uuidString).json",
            setupFilename: "test-drive-\(UUID().uuidString).json")
    }

    /// A closed, compilable layout — what the editor has when the button appears.
    private func drivableLayout() throws -> TrackLayout {
        let code = try XCTUnwrap(TrackLibrary.builtins.first).code
        return try TrackCode.decode(code)
    }

    func testATestDriveRacesTheEditorsTrackWithAIOnly() throws {
        let couch = game()
        // Race first, so the drive is replacing a real human rig rather than
        // building one from nothing — the case that has to end up with zero
        // bands rather than the previous race's four.
        couch.startRace()
        XCTAssertEqual(couch.rig?.players.count, 1, "fixture: a race seats its player")
        couch.editorLayout = try drivableLayout()
        couch.openEditor()
        couch.testDriveEditorTrack()

        XCTAssertEqual(couch.phase, .racing)
        XCTAssertTrue(couch.isTestDriving)
        let session = try XCTUnwrap(couch.session)
        XCTAssertEqual(session.race.cars.count, CouchGame.testDriveCars)
        // **The race must be PRESENTABLE, not merely started.** `GameView` shows
        // it only when there is both a session and a rig, so a nil rig rendered
        // a blank white screen and the whole feature was invisible — reported
        // from device. Asserting `rig == nil` (as this did) was asserting the
        // bug: what a test drive needs is a rig with no control bands.
        XCTAssertNotNil(couch.rig, "no rig — GameView would render nothing")
        XCTAssertEqual(
            couch.rig?.players.count, 0,
            "a test drive has no human seats: the author is watching the line")
        XCTAssertEqual(couch.aiFleet.drivers.count, CouchGame.testDriveCars)
        // And no ready gate — there are no thumbs to position.
        XCTAssertTrue(session.started)
    }

    /// **Back to the canvas exactly as it was.** The mode and the chosen track
    /// belong to the setup screen; a drive that left them changed would be a bug
    /// the author only noticed later, on a different screen.
    func testEndingADriveRestoresTheEditorAndTheSetup() throws {
        let couch = game()
        couch.mode = .tournament
        let chosen = TrackLibrary.builtins[1].id
        couch.trackID = chosen
        let layout = try drivableLayout()
        couch.editorLayout = layout
        couch.openEditor()

        couch.testDriveEditorTrack()
        XCTAssertEqual(couch.mode, .race, "a drive is a plain lap race")
        couch.endTestDrive()

        XCTAssertEqual(couch.phase, .editing)
        XCTAssertFalse(couch.isTestDriving)
        XCTAssertEqual(couch.mode, .tournament, "the mode was not put back")
        XCTAssertEqual(couch.trackID, chosen, "the chosen track was not put back")
        XCTAssertEqual(couch.editorLayout, layout, "the layout came back changed")
        XCTAssertNil(couch.session)
        XCTAssertTrue(couch.aiFleet.drivers.isEmpty)
    }

    /// A layout that will not compile has nothing to drive, so nothing happens —
    /// the button is absent in that state, and the model refuses anyway.
    func testAnUncompilableLayoutCannotBeDriven() {
        let couch = game()
        couch.openEditor()  // a lone start piece: an open end, no lap
        couch.editorLayout = TrackLayout(pieces: [])
        couch.testDriveEditorTrack()
        XCTAssertFalse(couch.isTestDriving)
        XCTAssertNotEqual(couch.phase, .racing)
    }

    /// **A test drive files no records.** The track exists for two minutes and
    /// has no human driver, so a lap time against it would be meaningless — and
    /// would pollute a real track's board if the ids ever collided.
    func testATestDriveRecordsNothing() throws {
        let couch = game()
        couch.editorLayout = try drivableLayout()
        couch.openEditor()
        couch.testDriveEditorTrack()
        let session = try XCTUnwrap(couch.session)

        // Run it far enough that laps complete.
        var time = 0.0
        while time < 120, session.race.cars[0].progress.lapTimes.isEmpty {
            time += 1.0 / 60
            session.advance(to: time)
            couch.noteProgress()
        }
        XCTAssertFalse(
            session.race.cars[0].progress.lapTimes.isEmpty,
            "the AI never completed a lap — fixture issue")
        XCTAssertNil(
            couch.hiscores.best(for: CouchGame.testDriveTrackID).bestLapTicks,
            "a test drive filed a record")
        XCTAssertNil(couch.runRecords.lapRecord)
    }

    /// **The drive never ends and never counts down.** A lap count would make
    /// the author wait for a finish before reading anything, and three seconds
    /// of a stationary car is three seconds of waiting to see the thing they
    /// asked to see. Reported: "I don't want to wait for three laps".
    func testADriveLapsForeverAndStartsAtOnce() throws {
        let couch = game()
        couch.editorLayout = try drivableLayout()
        couch.openEditor()
        couch.testDriveEditorTrack()
        let session = try XCTUnwrap(couch.session)
        XCTAssertNil(session.race.config.laps, "a lap limit makes the author wait")
        XCTAssertEqual(session.race.config.countdownTicks, 0, "nobody needs to get ready")
        XCTAssertEqual(
            session.race.cars.count, 1,
            "one car: three made the first number arrive three laps late")

        // Drive well past what would have been three laps: still going.
        var time = 0.0
        while time < 90 {
            time += 1.0 / 60
            session.advance(to: time)
        }
        XCTAssertNotEqual(session.race.phase, .finished, "the drive ended on its own")
        XCTAssertGreaterThan(
            session.race.cars[0].progress.lapTimes.count, 1,
            "several laps should have completed by now")
    }

    /// Peak speed is watched as the drive runs, since it is a property of the
    /// run — the authoring question is "does this track ever reach speed".
    func testPeakSpeedIsMeasuredDuringTheDrive() throws {
        let couch = game()
        couch.editorLayout = try drivableLayout()
        couch.openEditor()
        couch.testDriveEditorTrack()
        let session = try XCTUnwrap(couch.session)
        XCTAssertEqual(couch.testDrivePeakSpeed, 0, "nothing has moved yet")

        var time = 0.0
        while time < 30 {
            time += 1.0 / 60
            session.advance(to: time)
        }
        XCTAssertGreaterThan(couch.testDrivePeakSpeed, 0, "no speed was recorded")
    }

}
