import SkidCore
import SwiftUI

/// **Watching the AI drive the track you are building.**
///
/// Authoring tooling: the fastest way to know whether a corner works is to see
/// something take it, and the fastest way to know whether a lap is any good is
/// to be told the time. Both without leaving the editor — the track goes back on
/// the canvas exactly as it was, because a test drive is a question about the
/// design rather than a commitment to it.
///
/// **No human seats.** A test drive is a demonstration, not a race: the author
/// is watching the line, and a control band under their thumb would only get in
/// the way of that. The AI's own difficulty setting decides how hard it tries.
extension CouchGame {
    /// How many cars go out. Three is enough to see them interact — a single car
    /// takes an unobstructed line, which flatters a track that a field would
    /// find awkward — and few enough that a small layout is not a pile-up.
    public static let testDriveCars = 3

    /// **Race the editor's layout, remembering where to come back to.**
    ///
    /// Compiles what is on the canvas; refuses when it will not compile, since
    /// there is nothing to drive. The layout is not saved, promoted, or given an
    /// id that could collide with a library entry — it is a throwaway track for
    /// the length of the drive.
    public func testDriveEditorTrack() {
        guard let layout = editorLayout,
            let track = try? PieceCompiler.compile(layout, id: Self.testDriveTrackID)
        else { return }
        testDriveReturn = TestDriveReturn(
            mode: mode, trackID: trackID, layout: layout)
        // A test drive is its own field: every car is AI, however the setup
        // screen is configured, and the mode is a plain lap race whatever the
        // author was last playing.
        mode = .race
        aiColorIndices = Array(0..<Self.testDriveCars)
        let cars = Self.testDriveCars
        aiFleet.drivers = Dictionary(
            uniqueKeysWithValues: (0..<cars).map {
                (PlayerID($0), AIDriver.make(aiDifficulty, gridIndex: $0))
            })
        // **An EMPTY rig, not a nil one.** A test drive has no human seats, but
        // `GameView` shows the race only when there is both a session and a rig,
        // so nil rendered a blank white screen — the whole feature, invisible.
        // Reported from device. An empty rig is the honest object: a valid rig
        // with no control bands, which is exactly what a spectator view is.
        rig = CouchRig(colorIndices: [])
        seed += 1
        testDrivePeakSpeed = 0
        session = makeTestDriveSession(track: track, cars: cars)
        phase = .racing
    }

    /// Back to the canvas, exactly as it was.
    ///
    /// Restores what the drive replaced rather than assuming the editor was
    /// untouched: the mode and the chosen track both belong to the setup screen,
    /// and a test drive that quietly left the game in `.race` on a throwaway
    /// track would be a bug the author only noticed later.
    public func endTestDrive() {
        guard let saved = testDriveReturn else { return }
        testDriveReturn = nil
        session = nil
        rig = nil
        aiFleet.drivers = [:]
        sound.stop()
        mode = saved.mode
        trackID = saved.trackID
        editorLayout = saved.layout
        phase = .editing
    }

    /// Whether a race on screen is a test drive — the race chrome asks, so it
    /// can offer "Back to editor" instead of "Race again".
    public var isTestDriving: Bool { testDriveReturn != nil }

    /// Restart the drive on the same track: the author changed nothing, they
    /// just want to watch it again (or with a different AI skill).
    public func testDriveAgain() {
        guard let layout = testDriveReturn?.layout,
            let track = try? PieceCompiler.compile(layout, id: Self.testDriveTrackID)
        else { return }
        let cars = Self.testDriveCars
        aiFleet.drivers = Dictionary(
            uniqueKeysWithValues: (0..<cars).map {
                (PlayerID($0), AIDriver.make(aiDifficulty, gridIndex: $0))
            })
        seed += 1
        testDrivePeakSpeed = 0
        session = makeTestDriveSession(track: track, cars: cars)
    }

    /// The id a test-driven track carries. Deliberately not a library id and not
    /// `customTrackID`: nothing should file a record against a track that exists
    /// only for the next two minutes (`noteProgress` also refuses, since a test
    /// drive has no human seat).
    static let testDriveTrackID = "editor-test-drive"

    private func makeTestDriveSession(track: Track, cars: Int) -> GameSession {
        let players = (0..<cars).map { PlayerID($0) }
        notedLapCount = 0
        notedFinish = false
        notedCountdownSeconds = nil
        runRecords = .none
        let fleet = aiFleet
        let session = GameSession(
            track: track, players: players,
            // **Three laps, like a race.** A single lap would be all standing
            // start and no representative pace; the author wants to see a
            // settled lap, which is the second one onward.
            config: RaceConfig(laps: 3, countdownTicks: 3 * Race.tickRate),
            seed: seed, tuning: settings.carTuning,
            inputFor: { player, race in fleet.input(for: player, in: race) })
        session.onTick = { [weak self] race in
            guard let self else { return }
            // **Peak speed has to be watched, not asked for afterwards.** It is
            // a property of the run rather than of the final state, and the
            // authoring question it answers — "is there anywhere on this track
            // that reaches top speed?" — cannot be read off a stopped car.
            for car in race.cars {
                self.testDrivePeakSpeed = max(
                    self.testDrivePeakSpeed, car.state.velocity.length)
            }
            if self.settings.soundOn {
                self.sound.update(race: race, humanCount: 0, paused: false)
            }
        }
        // No ready gate: nobody's thumbs need positioning, so waiting for a tap
        // would just be a tap.
        session.started = true
        return session
    }
}

/// What a test drive has to put back when it ends.
struct TestDriveReturn: Equatable {
    var mode: CouchGame.Mode
    var trackID: String
    var layout: TrackLayout
}
