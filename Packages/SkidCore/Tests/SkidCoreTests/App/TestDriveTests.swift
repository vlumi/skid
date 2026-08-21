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
        // **Race first, so there IS a rig to clear.** Without this the assertion
        // below passes vacuously — the editor leaves `rig` nil anyway, so
        // removing the clear changed nothing and the sabotage went green.
        couch.startRace()
        XCTAssertNotNil(couch.rig, "fixture: a race should have left a rig")
        couch.editorLayout = try drivableLayout()
        couch.openEditor()
        couch.testDriveEditorTrack()

        XCTAssertEqual(couch.phase, .racing)
        XCTAssertTrue(couch.isTestDriving)
        let session = try XCTUnwrap(couch.session)
        XCTAssertEqual(session.race.cars.count, CouchGame.testDriveCars)
        // **No human seats**: the author is watching the line, not driving.
        XCTAssertNil(couch.rig)
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

    /// Driving again keeps the drive going rather than returning to the editor,
    /// and re-seeds so it is a fresh run rather than the same one replayed.
    func testDrivingAgainStaysInTheDrive() throws {
        let couch = game()
        couch.editorLayout = try drivableLayout()
        couch.openEditor()
        couch.testDriveEditorTrack()
        let first = try XCTUnwrap(couch.session)
        couch.testDriveAgain()
        let second = try XCTUnwrap(couch.session)
        XCTAssertTrue(couch.isTestDriving)
        XCTAssertEqual(couch.phase, .racing)
        XCTAssertNotEqual(first.raceKey, second.raceKey, "the same race was replayed")
    }
}
