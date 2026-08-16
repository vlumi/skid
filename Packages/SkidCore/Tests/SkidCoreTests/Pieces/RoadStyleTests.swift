import XCTest

@testable import SkidCore
@testable import SkidKit

/// **A road style is a property of the whole track, not a mark on a piece.**
///
/// It exists because lane markings are not decals: they cover every piece, they must
/// appear on pieces added later without being placed again, and a piece inserted
/// mid-track must not leave a gap. These pin the storage half of that.
final class RoadStyleTests: XCTestCase {
    private var layout: TrackLayout {
        TrackLayout(pieces: [PieceCatalog.startPieceID, 1, 1, 1])
    }

    /// **Circuit is the default**, so every existing track is unchanged.
    func testCircuitIsTheDefault() {
        XCTAssertEqual(layout.roadStyle, .circuit)
    }

    /// **A circuit's code is byte-identical to before the style existed.** The section is
    /// omitted at the default, which is what stops this change rewriting every code — and
    /// therefore every content-hashed library id.
    func testACircuitCodeCarriesNoStyleSection() throws {
        var road = layout
        road.roadStyle = .road
        let circuitCode = TrackCode.encode(layout)
        let roadCode = TrackCode.encode(road)
        XCTAssertNotEqual(circuitCode, roadCode, "the style must reach the code")
        XCTAssertLessThan(
            circuitCode.count, roadCode.count,
            "a circuit should be the SHORTER code — its style section is omitted")
    }

    /// It survives the wire.
    func testTheStyleRoundTrips() throws {
        for style in TrackLayout.RoadStyle.allCases {
            var original = layout
            original.roadStyle = style
            let back = try XCTUnwrap(try? TrackCode.decode(TrackCode.encode(original)))
            XCTAssertEqual(back.roadStyle, style)
        }
    }

    /// **An unknown style decodes as a circuit rather than failing.** A code from a
    /// later build should still be raceable, just plainer — refusing it would make a
    /// shared track unopenable over a purely cosmetic difference.
    func testAnUnknownStyleFallsBackToCircuit() {
        XCTAssertNil(
            TrackLayout.RoadStyle(rawValue: 99),
            "99 must be an unknown style for this test to mean anything")
        // What `decode` does with that nil, spelled out: the fallback, not a throw.
        let style = TrackLayout.RoadStyle(rawValue: 99) ?? .circuit
        XCTAssertEqual(style, .circuit)
    }
}

/// **Setting the style from the editor**, which is where a track author meets it.
@MainActor
final class EditedRoadStyleTests: XCTestCase {
    private func game() -> CouchGame {
        let unique = UUID().uuidString
        let game = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-lib-\(unique).json",
            profileFilename: "test-profiles-\(unique).json",
            hiscoreFilename: "test-hiscores-\(unique).json")
        game.editorLayout = TrackLayout(pieces: [PieceCatalog.startPieceID, 1, 1])
        return game
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

    /// **The style reaches the layout**, which is what the renderer reads.
    func testSettingTheStyleUpdatesTheLayout() {
        let game = self.game()
        XCTAssertEqual(game.editorLayout?.roadStyle, .circuit)
        game.setEditedRoadStyle(.road)
        XCTAssertEqual(game.editorLayout?.roadStyle, .road)
    }

    /// **It survives the round trip through the share code**, which is how a track is
    /// stored and passed on — a style that did not would be lost on reopening.
    func testTheStyleSurvivesTheTracksOwnCode() throws {
        let game = self.game()
        game.setEditedRoadStyle(.road)
        let layout = try XCTUnwrap(game.editorLayout)
        let back = try XCTUnwrap(try? TrackCode.decode(TrackCode.encode(layout)))
        XCTAssertEqual(back.roadStyle, .road)
    }

    /// Setting the style it already has changes nothing — no needless save.
    func testSettingTheSameStyleIsANoOp() {
        let game = self.game()
        let before = game.editorLayout
        game.setEditedRoadStyle(.circuit)
        XCTAssertEqual(game.editorLayout, before)
    }

    /// With no track open there is nothing to set, and nothing crashes.
    func testSettingWithNoLayoutIsHarmless() {
        let game = self.game()
        game.editorLayout = nil
        game.setEditedRoadStyle(.road)
        XCTAssertNil(game.editorLayout)
    }
}
