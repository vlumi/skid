import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Wiping everything has to mean everything.**
///
/// The failure mode is a reset that looks like it worked: the screen empties, and a
/// forgotten store puts a stale track or a tuned dial back on the next launch. So these
/// check the sweep is by prefix (not a list of names that will fall behind), that the
/// files go, and — the subtle one — that clearing the editor layout does not re-save the
/// files the wipe just deleted.
@MainActor
final class ResetAllDataTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        // A private defaults suite and a private directory: both stores are otherwise
        // process-wide, so this would empty the developer's own dials and tracks.
        suiteName = "skid.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("skid-reset-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func write(_ name: String) {
        try? Data("{}".utf8).write(to: directory.appendingPathComponent(name))
    }

    /// **The stored books go.**
    func testItDeletesTheStoredFiles() {
        for name in ["tracks.json", "profiles.json", "hiscores.json"] { write(name) }
        ResetAllData.wipe(defaults: defaults, directory: directory)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertTrue(left.isEmpty, "every stored book should be gone, found \(left)")
    }

    /// **Swept by PREFIX, not by a list of names.** A dial added next month is wiped by
    /// this without anybody remembering to come back and add it — which is the whole
    /// reason the sweep is written this way.
    func testItClearsEverySkidDefaultIncludingOnesNobodyListed() {
        defaults.set(1.23, forKey: "skid.sim.gripScale")
        defaults.set("x", forKey: "skid.editor.customTrack")
        defaults.set(true, forKey: "skid.debug.overlay")
        // A key that does not exist yet — stands in for whatever gets added later.
        defaults.set(9, forKey: "skid.some.futureDial")

        ResetAllData.wipe(defaults: defaults, directory: directory)

        for key in [
            "skid.sim.gripScale", "skid.editor.customTrack", "skid.debug.overlay",
            "skid.some.futureDial",
        ] {
            XCTAssertNil(defaults.object(forKey: key), "\(key) survived the wipe")
        }
    }

    /// **Somebody else's defaults are left alone**, since the sweep runs against the
    /// standard store in production — where the OS and other frameworks keep their own.
    func testItLeavesForeignDefaultsAlone() {
        defaults.set("keep", forKey: "unrelated.setting")
        defaults.set("keep", forKey: "AppleLanguages.pretend")
        ResetAllData.wipe(defaults: defaults, directory: directory)
        XCTAssertEqual(defaults.string(forKey: "unrelated.setting"), "keep")
        XCTAssertEqual(defaults.string(forKey: "AppleLanguages.pretend"), "keep")
    }

    /// Only the app's own JSON is removed — a stray file is not this function's business.
    func testItLeavesNonJSONFilesAlone() {
        write("tracks.json")
        try? Data("x".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        ResetAllData.wipe(defaults: defaults, directory: directory)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertEqual(left, ["notes.txt"])
    }

    /// An empty or missing directory is not an error — resetting twice is allowed.
    func testWipingTwiceIsHarmless() {
        write("hiscores.json")
        ResetAllData.wipe(defaults: defaults, directory: directory)
        ResetAllData.wipe(defaults: defaults, directory: directory)
        ResetAllData.wipe(
            defaults: defaults,
            directory: directory.appendingPathComponent("missing", isDirectory: true))
    }
}

/// **The game-level reset**, which is where the ordering trap lives.
@MainActor
final class GameResetTests: XCTestCase {
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

    /// **In-memory state empties too**, or the app keeps showing what was deleted — and
    /// re-saves it on the next change.
    func testItEmptiesTheGamesOwnState() {
        let game = self.game()
        game.hiscores.recordLap(500, track: "clover")
        game.profiles.put(PlayerProfile(name: "Ada", colorIndex: 0))
        XCTAssertFalse(game.profiles.profiles.isEmpty)

        game.resetAllData()

        XCTAssertTrue(game.hiscores.tracks.isEmpty)
        XCTAssertTrue(game.profiles.profiles.isEmpty)
        XCTAssertTrue(game.library.tracks.isEmpty)
        XCTAssertNil(game.editorLayout)
        XCTAssertEqual(game.entrants, [.guest])
        XCTAssertTrue(game.runRecords.isEmpty)
    }

    /// **The files stay gone, and an edited track does not come back with them.**
    ///
    /// Note what this does NOT prove: `resetAllData` clears memory before disk, and
    /// reversing that was measured to change nothing — `editorLayout = nil` writes no
    /// file, because `saveCustomTrack` only removes the key when there is no track and
    /// `syncEditedTrackToLibrary` returns on its `guard let layout`. The order is kept as
    /// defence against those changing, not because it is currently load-bearing, and no
    /// test here can claim otherwise.
    func testAnEditedTrackDoesNotSurviveTheWipe() {
        let game = self.game()
        game.editorLayout = TrackLibrary.track(id: "clover").layout
        game.hiscores.recordLap(500, track: "clover")

        game.resetAllData()

        let directory = ResetAllData.directory()
        let left = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let mine = left.filter { $0.hasPrefix("test-") }
        XCTAssertTrue(mine.isEmpty, "the wipe left files behind: \(mine)")
        XCTAssertTrue(game.library.tracks.isEmpty, "the library came back")
    }

    /// A reset leaves the app at the front door rather than in a race whose data is gone.
    func testItReturnsToTheFrontDoor() {
        let game = self.game()
        game.openSetup()
        game.resetAllData()
        XCTAssertEqual(game.phase, .menu)
        XCTAssertNil(game.session)
    }
}
