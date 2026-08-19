import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The setup survives quitting** — who is racing, on which track, in which
/// mode — and comes back sane when what it referred to is gone.
@MainActor
final class SetupMemoryTests: XCTestCase {
    /// One setup file per TEST, shared by its two "launches" — the relaunch is
    /// the point — and never by another test.
    private var setupFilename = ""

    override func setUp() {
        super.setUp()
        setupFilename = "test-setup-\(UUID().uuidString).json"
    }

    private func game() -> CouchGame {
        CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-setup-\(UUID().uuidString).json",
            profileFilename: "test-setup-\(UUID().uuidString).json",
            setupFilename: setupFilename)
    }

    func testTheSetupSurvivesARelaunch() {
        let before = game()
        before.mode = .timeTrial
        before.trackID = TrackLibrary.builtins[2].id
        before.addEntrant(.guest)
        before.schemes[0] = .pro
        before.fillWithAI = false
        before.aiDifficulty = .hard

        let after = game()
        XCTAssertEqual(after.mode, .timeTrial)
        XCTAssertEqual(after.trackID, TrackLibrary.builtins[2].id)
        XCTAssertEqual(after.entrants.count, 2)
        XCTAssertEqual(after.schemes[0], .pro)
        XCTAssertFalse(after.fillWithAI)
        XCTAssertEqual(after.aiDifficulty, .hard)
    }

    /// A remembered entrant whose profile was deleted races as a guest, not as
    /// a dangling id; a remembered track that no longer exists falls back.
    func testMissingReferencesDegradeSafely() throws {
        let memory = SetupMemory(
            mode: .race, trackID: "no-such-track",
            entrants: [.profile(UUID()), .guest],
            schemes: [.pro, .casual, .casual, .casual],
            fillWithAI: true, aiDifficulty: .medium)
        SetupFile(filename: setupFilename).save(memory)
        let after = game()
        XCTAssertEqual(after.trackID, TrackLibrary.builtins[0].id, "a gone track must fall back")
        XCTAssertEqual(
            after.entrants.map(\.kind), [.guest, .guest],
            "a deleted profile must race as a guest")
    }
}
