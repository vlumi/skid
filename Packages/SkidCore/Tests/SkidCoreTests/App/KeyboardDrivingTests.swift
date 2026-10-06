import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Keys drive the race the game actually builds** — through `handle(_:)`,
/// the input tap, the session and the sim, the same route a Mac key press
/// takes. A source that works in isolation proves nothing about the wiring.
@MainActor
final class KeyboardDrivingTests: XCTestCase {
    private func game(humans: Int) -> CouchGame {
        let couch = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "keys-\(UUID().uuidString).json",
            profileFilename: "keys-\(UUID().uuidString).json",
            setupFilename: "keys-\(UUID().uuidString).json")
        couch.keyboardDriving = true
        couch.fillWithAI = false
        couch.trackID = "oval"
        couch.mode = .race
        couch.playerCount = humans
        couch.startRace()
        return couch
    }

    /// Advances the race a fixed number of seconds — bounded, never a `while`
    /// on sim state, which once hung the whole suite.
    private func run(_ couch: CouchGame, seconds: Double, from start: inout Double) {
        guard let session = couch.session else { return XCTFail("no session") }
        for _ in 0..<Int(seconds * 60) {
            start += 1.0 / 60
            session.advance(to: start)
        }
    }

    private func speed(_ couch: CouchGame, seat: Int) -> Double {
        couch.session?.race.cars[seat].state.velocity.length ?? -1
    }

    /// **WASD is P1, the arrows are P2** — each drives its own car only.
    func testTwoDriversEachDriveTheirOwnCar() throws {
        let couch = game(humans: 2)
        XCTAssertTrue(couch.handle(.start), "Space did not leave the ready gate")
        var t = 0.0
        run(couch, seconds: 0.1, from: &t)
        run(couch, seconds: 3.5, from: &t)  // the countdown
        XCTAssertTrue(couch.handle(.drive(.w, down: true)))
        run(couch, seconds: 1, from: &t)
        XCTAssertGreaterThan(speed(couch, seat: 0), 50, "W did not drive P1")
        XCTAssertLessThan(speed(couch, seat: 1), 1, "W leaked into P2's car")

        couch.handle(.drive(.w, down: false))
        couch.handle(.drive(.up, down: true))
        run(couch, seconds: 1, from: &t)
        XCTAssertGreaterThan(speed(couch, seat: 1), 50, "↑ did not drive P2")
    }

    /// **The keyboard's own turn rate reaches the sim**: a held D at speed
    /// asks for LESS than full lock (the scaled wheel), and the recording —
    /// what a ghost replays — holds that scaled value, not the raw key.
    func testHeldKeysAreScaledToTheKeyboardTurnRate() throws {
        let couch = game(humans: 1)
        couch.settings.keyboardTurnRate = 2
        couch.applyControlTuning()
        XCTAssertEqual(couch.keyboard.turnRate, 2, "the dial never reached the keyboard")
        couch.handle(.start)
        var t = 0.0
        run(couch, seconds: 3.6, from: &t)
        couch.handle(.drive(.w, down: true))
        run(couch, seconds: 1, from: &t)
        couch.handle(.drive(.d, down: true))
        run(couch, seconds: 0.2, from: &t)
        let steer = try XCTUnwrap(couch.session?.recording.inputs.last?[PlayerID(0)]).steer
        XCTAssertGreaterThan(steer, 0.3, "D did not steer")
        XCTAssertLessThan(steer, 0.95, "the key went in at full lock, unscaled")
    }

    /// A lone driver drives with either hand.
    func testALoneDriverUsesEitherCluster() {
        let couch = game(humans: 1)
        couch.handle(.start)
        var t = 0.0
        run(couch, seconds: 3.6, from: &t)
        couch.handle(.drive(.up, down: true))
        run(couch, seconds: 1, from: &t)
        XCTAssertGreaterThan(speed(couch, seat: 0), 50, "↑ did not drive the only car")
    }

    /// **Two seats on a keyboard**: a third would have no keys, and a restored
    /// four-seat setup is cut back rather than seating keyless drivers.
    func testAKeyboardSeatsAtMostTwo() {
        let couch = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "keys-\(UUID().uuidString).json",
            profileFilename: "keys-\(UUID().uuidString).json",
            setupFilename: "keys-\(UUID().uuidString).json")
        couch.playerCount = 4
        XCTAssertEqual(couch.playerCount, 4, "fixture: touch seats four")
        couch.keyboardDriving = true
        XCTAssertEqual(couch.playerCount, 2, "four seats survived the switch to keys")
        XCTAssertFalse(couch.canAdd(), "a third keyboard seat was offered")
        couch.playerCount = 3
        XCTAssertEqual(couch.playerCount, 2)
    }

    /// **Space starts, Escape pauses and resumes** — and neither does anything
    /// out of turn: no pause before the start, no second "start". Out of turn
    /// they are still SWALLOWED, or the system beeps at every press mid-race.
    func testSpaceStartsAndEscapePauses() throws {
        let couch = game(humans: 1)
        let session = try XCTUnwrap(couch.session)
        XCTAssertTrue(couch.handle(.pause), "Escape before the start would beep")
        XCTAssertFalse(session.paused, "paused a race that had not started")
        XCTAssertTrue(couch.handle(.start))
        XCTAssertTrue(session.started)
        XCTAssertTrue(couch.handle(.start), "Space after the start would beep")
        XCTAssertFalse(session.paused, "a second Space paused the race")
        XCTAssertTrue(couch.handle(.pause))
        XCTAssertTrue(session.paused)
        couch.handle(.pause)
        XCTAssertFalse(session.paused, "Escape did not resume")
    }

    /// **Outside a race the keys belong to the UI** — a press passes through
    /// so an editor text field still types — but a key-UP always lands, so a
    /// key let go during the results card is not held into the rematch.
    func testKeysPassThroughOutsideARaceButReleasesAlwaysLand() {
        let couch = game(humans: 1)
        couch.handle(.drive(.w, down: true))
        couch.backToMenu()
        XCTAssertFalse(couch.handle(.drive(.a, down: true)), "the menu ate a keystroke")
        XCTAssertFalse(couch.keyboard.seats[0].held.contains(.a))
        couch.handle(.drive(.w, down: false))
        XCTAssertFalse(couch.keyboard.seats[0].held.contains(.w), "W stuck down")
    }

    #if os(macOS)
    /// The Mac's PHYSICAL key codes, and ⌘ never driving — ⌘W closes, ⌘T tunes.
    func testMacKeyCodesMapToTheGame() {
        XCTAssertEqual(
            KeyEvent(macKeyCode: 0x0D, down: true, command: false), .drive(.w, down: true))
        XCTAssertEqual(
            KeyEvent(macKeyCode: 0x7C, down: false, command: false), .drive(.right, down: false))
        XCTAssertEqual(KeyEvent(macKeyCode: 0x31, down: true, command: false), .start)
        XCTAssertEqual(KeyEvent(macKeyCode: 0x35, down: true, command: false), .pause)
        XCTAssertNil(KeyEvent(macKeyCode: 0x0D, down: true, command: true), "⌘W drove")
        XCTAssertNil(
            KeyEvent(macKeyCode: 0x31, down: false, command: false), "a Space key-up started")
        XCTAssertNil(KeyEvent(macKeyCode: 0x0C, down: true, command: false), "Q meant something")
    }
    #endif
}
