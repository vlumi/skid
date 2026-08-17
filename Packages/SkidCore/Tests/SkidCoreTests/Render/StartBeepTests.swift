import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The countdown's beeps: three counting blips, then a different one on go.**
///
/// The property that matters is "exactly once per second boundary". The audio frame runs
/// at display rate, so anything shaped like "is the clock near a second?" fires the same
/// beep on every frame it is near one — a machine-gun countdown.
final class StartBeepTests: XCTestCase {
    /// **A beep only where the second actually changes.** Same value in, nothing out.
    func testNoBeepWhileTheSecondHoldsSteady() {
        for seconds in 1...3 {
            XCTAssertNil(
                StartBeeps.beep(secondsBefore: seconds, secondsAfter: seconds),
                "\(seconds)s → \(seconds)s beeped, so it would beep every frame")
        }
    }

    /// **Counting down beeps, and they are the ordinary blip.**
    func testCountingBoundariesBeep() {
        XCTAssertEqual(StartBeeps.beep(secondsBefore: 3, secondsAfter: 2), false)
        XCTAssertEqual(StartBeeps.beep(secondsBefore: 2, secondsAfter: 1), false)
    }

    /// **The start is the FINAL beep** — the different one, so "go" does not sound like
    /// a fourth count.
    func testTheStartIsTheFinalBeep() {
        XCTAssertEqual(StartBeeps.beep(secondsBefore: 1, secondsAfter: 0), true)
        // The phase leaves `.countdown` entirely on the same frame — same event.
        XCTAssertEqual(StartBeeps.beep(secondsBefore: 1, secondsAfter: nil), true)
    }

    /// **Nothing beeps once the race is running**, however many frames go by.
    func testNoBeepsDuringTheRace() {
        XCTAssertNil(StartBeeps.beep(secondsBefore: nil, secondsAfter: nil))
        XCTAssertNil(StartBeeps.beep(secondsBefore: 0, secondsAfter: nil))
        XCTAssertNil(StartBeeps.beep(secondsBefore: 0, secondsAfter: 0))
    }

    /// **A whole countdown produces exactly four beeps** — one per light state, plus the
    /// start — driven tick by tick through a real race.
    ///
    /// Four, matching the gantry: three low beeps as the lights fill (including the
    /// opening state, which used to be silent) and the higher one when they go out. The
    /// lights and the beeps are the same countdown and must not disagree.
    func testARealCountdownBeepsOncePerLightState() {
        let track = TrackLibrary.track(id: "clover")
        var race = Race(
            track: track, players: [PlayerID(0)], seed: 1,
            config: RaceConfig(laps: 3, countdownTicks: 3 * Race.tickRate))
        var beeps: [Bool] = []
        // **Starts nil, exactly as the real caller does.** Seeding this from the race
        // before the loop is what let the old "three beeps" test pass while the opening
        // light state was silent — the test modelled the buggy caller rather than the
        // real one, so it could not see the missing beep.
        var previous: Int?
        // Well past the start, so a stray late beep would show up too.
        for _ in 0..<(Race.tickRate * 4) {
            race.advance(inputs: [PlayerID(0): .coast])
            let now = StartBeeps.secondsRemaining(in: race)
            if let isFinal = StartBeeps.beep(secondsBefore: previous, secondsAfter: now) {
                beeps.append(isFinal)
            }
            previous = now
        }
        XCTAssertEqual(
            beeps, [false, false, false, true],
            "expected three counting beeps and one start beep, got \(beeps)")
    }

    /// **A beep for every change of the lights, and no others.**
    ///
    /// The requirement in one test: the gantry and the countdown tones are the same
    /// countdown, so every frame that changes the lit pattern makes a sound, and every
    /// frame that does not is silent. This walks a real race and compares the two
    /// directly rather than trusting each half separately.
    func testEveryChangeOfTheLightsMakesExactlyOneSound() {
        let track = TrackLibrary.track(id: "clover")
        var race = Race(
            track: track, players: [PlayerID(0)], seed: 1,
            config: RaceConfig(laps: 3, countdownTicks: 3 * Race.tickRate))

        func lamps(_ race: Race) -> [Bool] {
            StartLights.pattern(secondsRemaining: StartBeeps.secondsRemaining(in: race) ?? 0)
        }
        // Both start from "nothing yet", as the app does: the gantry is not on screen
        // before the countdown, so its first appearance IS a change — which is the very
        // change that used to happen in silence.
        var previousSeconds: Int?
        var previousLamps = StartLights.pattern(secondsRemaining: 0)
        var changes = 0
        var sounds = 0
        for _ in 0..<(Race.tickRate * 4) {
            race.advance(inputs: [PlayerID(0): .coast])
            let now = StartBeeps.secondsRemaining(in: race)
            let beeped = StartBeeps.beep(secondsBefore: previousSeconds, secondsAfter: now) != nil
            let nowLamps = lamps(race)
            let lightsChanged = nowLamps != previousLamps
            if lightsChanged { changes += 1 }
            if beeped { sounds += 1 }
            XCTAssertEqual(
                beeped, lightsChanged,
                "lights and beep disagreed at \(String(describing: now))s: "
                    + "lights changed \(lightsChanged), beeped \(beeped)")
            previousSeconds = now
            previousLamps = nowLamps
        }
        XCTAssertEqual(changes, 4, "the gantry should change four times")
        XCTAssertEqual(sounds, changes)
    }

    /// The seconds shown match the gantry's, so a beep lands on the light it belongs to.
    func testSecondsRoundUpLikeTheLights() {
        let track = TrackLibrary.track(id: "clover")
        let race = Race(
            track: track, players: [PlayerID(0)], seed: 1,
            config: RaceConfig(laps: 3, countdownTicks: 3 * Race.tickRate))
        XCTAssertEqual(StartBeeps.secondsRemaining(in: race), 3)
    }
}

/// **No countdown sound before the race starts.**
///
/// Reported from device: the first beep played the instant the race screen appeared,
/// before pressing Play. The sim sits frozen at tick 0 in `.countdown` while the ready
/// gate holds — three seconds showing, nothing moving — so the frame callback saw
/// "the countdown just began" on the very first frame.
@MainActor
final class CountdownBeepGateTests: XCTestCase {
    private func game() -> CouchGame {
        let unique = UUID().uuidString
        return CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-lib-\(unique).json",
            profileFilename: "test-profiles-\(unique).json",
            hiscoreFilename: "test-hiscores-\(unique).json")
    }

    override func tearDown() {
        super.tearDown()
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Skid", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasPrefix("test-") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// A session waiting on the ready gate, exactly as the race screen makes one.
    private func waiting(_ game: CouchGame) -> GameSession {
        let track = TrackLibrary.track(id: "clover")
        let session = GameSession(
            track: track, players: [PlayerID(0)],
            config: RaceConfig(laps: 3, countdownTicks: 3 * Race.tickRate), seed: 42,
            inputFor: { _, _ in .coast })
        game.session = session
        game.rig = CouchRig(colorIndices: [0])
        game.phase = .racing
        return session
    }

    /// **Frames before Play make no sound.** The countdown is showing 3, but it has not
    /// begun — nothing has changed yet, so nothing should be heard.
    func testNoBeepWhileWaitingOnTheReadyGate() {
        let game = self.game()
        let session = waiting(game)
        XCTAssertFalse(session.started)
        for _ in 0..<30 {
            game.audioFrame()
        }
        XCTAssertNil(
            game.notedCountdownSeconds,
            "the countdown was tracked before it began, so its first beep already fired")
    }

    /// **And pressing Play still gives the opening beep.** Suppressing the early frames
    /// must not cost the first sound — the lights appear on that frame too.
    func testTheOpeningBeepSurvivesTheGate() {
        let game = self.game()
        let session = waiting(game)
        for _ in 0..<10 { game.audioFrame() }  // waiting: nothing tracked
        session.started = true
        game.audioFrame()  // the frame Play lands on
        XCTAssertEqual(
            game.notedCountdownSeconds, 3,
            "the countdown should start being tracked the moment the race does")
    }
}
