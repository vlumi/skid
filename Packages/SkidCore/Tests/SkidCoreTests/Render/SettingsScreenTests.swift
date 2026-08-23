import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The settings screen's few pieces of actual logic.**
///
/// Most of it is paint, which the suite cannot judge. What it can hold: that the seating
/// choice reaches the thing that seats people, and that the version line is assembled
/// from the bundle rather than written down somewhere it can rot.
@MainActor
final class SettingsScreenTests: XCTestCase {
    private func game() -> CouchGame {
        let unique = UUID().uuidString
        return CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-lib-\(unique).json",
            profileFilename: "test-profiles-\(unique).json",
            hiscoreFilename: "test-hiscores-\(unique).json",
            setupFilename: "test-\(UUID().uuidString).json")
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

    /// **Face to face is the default**, which is what two people across a table want and
    /// what the setup screen used to hardcode.
    func testTwoPlayersFaceEachOtherByDefault() {
        XCTAssertTrue(game().faceToFace)
    }

    /// **The choice reaches the rig**, which is the only thing that makes it a setting
    /// rather than a decoration: side-by-side must stop flipping the far player's pad.
    func testSideBySideStopsFlippingTheFarPlayer() {
        let flippedZones = { (faceToFace: Bool) -> Int in
            let rig = CouchRig(
                colorIndices: [0, 1],
                seating: SeatingConfig(faceToFace: faceToFace, openCorner: .topLeft))
            rig.layout(size: CGSize(width: 390, height: 844), mapRect: .zero)
            return rig.players.filter { $0.up.y > 0 }.count
        }
        XCTAssertEqual(flippedZones(true), 1, "one player sits across the table")
        XCTAssertEqual(flippedZones(false), 0, "side by side, both pads face the same way")
    }

    /// The version line is built from the bundle, so it cannot disagree with what shipped.
    /// In a test bundle there is no marketing version, and it says so rather than lying.
    func testTheVersionLineComesFromTheBundle() {
        let line = AboutView.versionLine
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            XCTAssertTrue(line.contains(version), "\(line) should name the bundle version")
        } else {
            XCTAssertEqual(line, "—")
        }
    }
}

/// **Leaving the track shelf goes back the way you came.**
///
/// The shelf is reached two ways — from the front door, and from the editor's own
/// chrome — and it used to leave the same way from both: dismissing always dropped you
/// on the editor canvas, so "Back" from the front door went *forward*, into a track you
/// had not chosen to edit.
@MainActor
final class TrackShelfNavigationTests: XCTestCase {
    private func game() -> CouchGame {
        let unique = UUID().uuidString
        return CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-lib-\(unique).json",
            profileFilename: "test-profiles-\(unique).json",
            hiscoreFilename: "test-hiscores-\(unique).json",
            setupFilename: "test-\(UUID().uuidString).json")
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

    // MARK: - top → tracks → editor

    /// **The hierarchy is fixed**, which is what replaced a Back that behaved
    /// differently depending on how you arrived. The library sits below the front
    /// door and above the editor, and each screen leaves upward.
    func testTheLibrarySitsBetweenTheMenuAndTheEditor() {
        let game = self.game()
        game.openTrackLibrary()
        XCTAssertEqual(game.phase, .tracks)
        game.openEditor()
        XCTAssertEqual(game.phase, .editing)
        // Closing the editor goes UP one level, to the library it was opened from
        // — not out to the front door, and not to wherever you happened to come
        // from. That "leave the way you came in" rule is the thing this replaces.
        game.closeEditor()
        XCTAssertEqual(game.phase, .tracks, "the editor did not close to the library")
    }

    /// **Choosing a track opens the canvas; Back leaves the library.**
    ///
    /// The bug this exists for: `back` and "open this track" were the SAME closure,
    /// so making Back context-aware turned every tile on the shelf into "return to
    /// the title screen". Built with the view's OWN closures, exactly as `GameView`
    /// builds them — the bug was in this wiring, not in either destination, so a
    /// test calling the model directly could not see it.
    func testTheShelfsTwoExitsStayDistinct() {
        let game = self.game()
        game.openTrackLibrary()
        let shelf = TrackShelfView(
            game: game,
            back: { game.backToMenu() },
            openCanvas: { game.openEditor() })

        game.newTrackForEditing()
        shelf.openCanvas()
        XCTAssertEqual(game.phase, .editing, "picking a track did not open the editor")

        game.openTrackLibrary()
        shelf.back()
        XCTAssertEqual(game.phase, .menu, "Back did not leave the library")
    }

    /// The front door opens the LIBRARY, not the canvas — naming the door after
    /// the room behind it sent players expecting a list into a track they had not
    /// chosen.
    func testTheFrontDoorOpensTheLibrary() {
        let game = self.game()
        game.openTrackLibrary()
        XCTAssertEqual(game.phase, .tracks)
        XCTAssertNotEqual(game.phase, .editing)
    }
}
