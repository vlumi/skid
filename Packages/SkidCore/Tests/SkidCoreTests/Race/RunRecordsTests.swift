import XCTest

@testable import SkidCore
@testable import SkidKit

/// **What a run takes off the record book, and whether the screen can say so.**
///
/// The subject is a timing problem, not arithmetic: `noteProgress` writes the record as
/// the lap lands, so afterwards the book agrees with the run and "was that a record?"
/// answers yes for every lap. The previous time has to be captured at the write, and
/// these are what prove it is.
///
/// Every test uses its own hiscore file — a fixed path is process-wide state, so these
/// would otherwise read and overwrite the developer's real records.
@MainActor
final class RunRecordsTests: XCTestCase {
    private var filenames: [String] = []

    /// A fresh game with its own on-disk books, seated for a qualifying solo run.
    private func game() -> CouchGame {
        let unique = UUID().uuidString
        let hiscores = "test-hiscores-\(unique).json"
        filenames.append(hiscores)
        let game = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-lib-\(unique).json",
            profileFilename: "test-profiles-\(unique).json",
            hiscoreFilename: hiscores)
        return game
    }

    /// A session an AI drives, seated for one human.
    ///
    /// Built directly rather than through `startRace`, because the real input source reads
    /// the touch rig — headless, that is a car that never moves and a test that proves
    /// nothing. Everything under test (`noteProgress`) reads the session, not the rig.
    private func seat(_ game: CouchGame, laps: Int?) -> GameSession {
        let track = TrackLibrary.track(id: "clover")
        var ai = AIDriver()
        let session = GameSession(
            track: track, players: [PlayerID(0)],
            config: RaceConfig(laps: laps, countdownTicks: 3 * Race.tickRate),
            seed: 42,
            inputFor: { _, race in ai.input(car: race.cars[0].state, track: track) })
        session.started = true
        game.session = session
        // `noteProgress` gates on the RIG's seat count — records are personal, so one
        // human or nothing. Without a rig the guard falls through and nothing records.
        game.rig = CouchRig(colorIndices: [0])
        // The physics dials live in process-wide `UserDefaults`, so a machine that has
        // been tuned records nothing — this test would then pass or fail depending on
        // whether the developer had touched the tuning panel.
        game.settings.pace = 1
        game.settings.resetPhysics()
        game.notedLapCount = 0
        game.notedFinish = false
        game.runRecords = .none
        return session
    }

    override func tearDown() {
        super.tearDown()
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Skid", isDirectory: true)
        for file in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] {
            if file.hasPrefix("test-hiscores-") || file.hasPrefix("test-profiles-")
                || file.hasPrefix("test-lib-")
            {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
        }
    }

    /// Drive until the run has banked `laps` laps (or the budget runs out), calling
    /// `noteProgress` every frame exactly as the race screen does.
    @discardableResult
    private func drive(_ session: GameSession, _ game: CouchGame, laps: Int) -> Int {
        var time = 0.0
        for _ in 0..<(60 * 120) {
            if session.race.cars[0].progress.lapTimes.count >= laps { break }
            time += Race.dt
            session.advance(to: time)
            game.noteProgress()
        }
        return session.race.cars[0].progress.lapTimes.count
    }

    /// **The first lap on a track is a record with nothing behind it**, and says so rather
    /// than inventing a time it beat.
    func testAFirstLapIsARecordWithNoPrevious() throws {
        let game = self.game()
        let session = seat(game, laps: nil)
        XCTAssertGreaterThan(drive(session, game, laps: 1), 0, "the AI should complete a lap")
        let lap = try XCTUnwrap(game.runRecords.lapRecord)
        XCTAssertNil(lap.previous, "nothing was there before, so nothing was beaten")
    }

    /// **The beaten time is kept**, which is the whole point — "beat 0:05.28" is the
    /// achievement, where "best lap 0:04.81" is only a number.
    ///
    /// Runs two races against ONE book: the second starts with the first's record standing,
    /// so any improvement must report it.
    func testASecondRunReportsTheTimeItBeat() throws {
        let game = self.game()
        let first = seat(game, laps: nil)
        drive(first, game, laps: 1)
        let trackID = first.race.track.id
        XCTAssertNotNil(game.hiscores.best(for: trackID).bestLapTicks)

        // Plant a slow record so the next run is guaranteed to beat it, rather than
        // relying on the AI driving faster the second time.
        var book = game.hiscores
        book.tracks[trackID]?.bestLapTicks = 100_000
        game.hiscores = book

        let second = seat(game, laps: nil)
        drive(second, game, laps: 1)
        let lap = try XCTUnwrap(game.runRecords.lapRecord, "a lap under the record must set it")
        XCTAssertEqual(lap.previous, 100_000, "the beaten time must be the one that stood")
        XCTAssertLessThan(lap.ticks, 100_000)
    }

    /// **A lap that does not beat the record leaves the run's records empty**, so the
    /// screen stays quiet rather than congratulating an ordinary lap.
    func testAnOrdinaryLapSetsNoRecord() {
        let game = self.game()
        let first = seat(game, laps: nil)
        drive(first, game, laps: 1)

        // Plant an unbeatable record, then drive again.
        var book = game.hiscores
        book.tracks[first.race.track.id]?.bestLapTicks = 1
        game.hiscores = book

        let second = seat(game, laps: nil)
        XCTAssertGreaterThan(drive(second, game, laps: 2), 0, "laps were driven")
        XCTAssertNil(game.runRecords.lapRecord, "nothing beat a 1-tick record")
        XCTAssertTrue(game.runRecords.isEmpty)
    }

    /// **A trial never sets a race record**, because it never finishes — the asymmetry the
    /// whole feature is shaped around.
    func testATimeTrialSetsNoRaceRecord() {
        let game = self.game()
        let session = seat(game, laps: nil)
        drive(session, game, laps: 3)
        XCTAssertNotNil(game.runRecords.lapRecord, "laps still count in a trial")
        XCTAssertNil(game.runRecords.raceRecord)
        XCTAssertNil(session.race.cars[0].progress.finishedAt, "a trial never finishes")
    }

    /// **A finished race sets both**, since a race has an ending for the race record to
    /// attach to.
    func testAFinishedRaceSetsBothRecords() {
        let game = self.game()
        let session = seat(game, laps: 2)
        drive(session, game, laps: 2)
        // One more frame: the finish lands on the tick the last lap does.
        session.advance(to: Double(session.race.tick + 1) * Race.dt)
        game.noteProgress()
        XCTAssertNotNil(session.race.cars[0].progress.finishedAt, "the race must finish")
        XCTAssertNotNil(game.runRecords.lapRecord)
        XCTAssertNotNil(game.runRecords.raceRecord)
    }

    /// **Records reset between runs**, so last race's news cannot linger on this race's
    /// results screen.
    func testStartingARaceClearsTheLastRunsRecords() {
        let game = self.game()
        let session = seat(game, laps: nil)
        drive(session, game, laps: 1)
        XCTAssertFalse(game.runRecords.isEmpty)
        game.entrants = [.guest]
        game.startRace()
        XCTAssertTrue(game.runRecords.isEmpty)
    }

    /// **A two-human race records nothing**, which is the existing rule — and the record
    /// line must stay silent rather than reporting a record that was never written.
    /// **A named player's record carries their name**, end to end: seat a profile, drive,
    /// and the book has the name — not just that `recordLap` can store one.
    func testANamedPlayersRecordCarriesTheirName() throws {
        let game = self.game()
        let profile = try XCTUnwrap(
            game.createProfile(named: "Ada", colorIndex: 0, forSeat: 0))
        let session = seat(game, laps: nil)
        game.setEntrant(.profile(profile.id), at: 0)
        drive(session, game, laps: 1)
        XCTAssertEqual(
            game.hiscores.best(for: session.race.track.id).lapHolder, "Ada",
            "the run recorded no name for a named player")
    }

    /// **A guest's record stores no name**, which is the default path.
    func testAGuestsRunStoresNoName() {
        let game = self.game()
        let session = seat(game, laps: nil)
        drive(session, game, laps: 1)
        XCTAssertNotNil(game.hiscores.best(for: session.race.track.id).bestLapTicks)
        XCTAssertNil(game.hiscores.best(for: session.race.track.id).lapHolder)
    }

    func testATwoPlayerRaceRecordsNothing() {
        let game = self.game()
        let track = TrackLibrary.track(id: "clover")
        var ai = AIDriver()
        let session = GameSession(
            track: track, players: [PlayerID(0), PlayerID(1)],
            config: RaceConfig(laps: 3, countdownTicks: 3 * Race.tickRate), seed: 42,
            inputFor: { _, race in ai.input(car: race.cars[0].state, track: track) })
        session.started = true
        game.session = session
        game.rig = CouchRig(colorIndices: [0, 1])
        game.settings.pace = 1
        game.settings.resetPhysics()
        game.runRecords = .none
        var time = 0.0
        for _ in 0..<(60 * 40) {
            time += Race.dt
            session.advance(to: time)
            game.noteProgress()
        }
        XCTAssertGreaterThan(
            session.race.cars[0].progress.lapTimes.count, 0, "laps were driven")
        XCTAssertTrue(game.runRecords.isEmpty, "two humans set no records")
    }
}

/// **The way back to stock**, which is what makes a tuned phone able to record again.
@MainActor
final class StockPhysicsTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        GameSettings().resetPhysics()
    }

    /// A dialed car records nothing, and resetting restores it — the whole reason the
    /// button exists. Dials live in process-wide `UserDefaults`, so this restores them.
    func testResettingRestoresStockAndSoRecording() {
        let settings = GameSettings()
        settings.resetPhysics()
        XCTAssertTrue(settings.isStockPhysics, "a reset must land on stock")

        settings.gripScale += 0.5
        XCTAssertFalse(settings.isStockPhysics, "a dialed car is not stock")

        settings.resetPhysics()
        XCTAssertTrue(settings.isStockPhysics, "and there is a way back")
        XCTAssertEqual(settings.gripScale, CarTuning().gripScale, accuracy: 1e-9)
    }

    /// Every dial `isStockPhysics` reads is one `resetPhysics` writes — otherwise the
    /// button would leave a knob behind and records would stay silently off.
    func testResetCoversEveryDialTheStockCheckReads() {
        let settings = GameSettings()
        settings.resetPhysics()
        let dials: [ReferenceWritableKeyPath<GameSettings, Double>] = [
            \.aimTurnRate, \.aimFlipBoost, \.steerFlipBoost, \.driftRetention,
            \.turnRate, \.gripScale, \.wallRestitution, \.wallGlanceBounce,
            \.wallFriction, \.wallDragFloor, \.gravity, \.wallYaw,
        ]
        for dial in dials {
            settings[keyPath: dial] += 0.25
            XCTAssertFalse(settings.isStockPhysics, "a moved dial must read as non-stock")
            settings.resetPhysics()
            XCTAssertTrue(settings.isStockPhysics, "and the reset must put it back")
        }
    }
}
