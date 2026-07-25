import XCTest

@testable import SkidCore

/// The custom-track slot's mechanism: a built design compiles to a drivable
/// track, and its share code round-trips exactly — that code is what gets
/// pasted into the repo to promote a design to a built-in, so it has to be
/// faithful.
final class CustomTrackTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    /// A closed rounded square: the simplest thing a player can build and race.
    private let square: [PieceID] = [
        Pieces.startGrid, Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
        Pieces.straight, Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
    ]

    func testABuiltTrackCompilesToSomethingDrivable() throws {
        let layout = TrackLayout(pieces: square, gateSeams: [0, 2, 4, 6])
        XCTAssertTrue(TrackValidator.validate(layout).isSaveable)
        let track = try PieceCompiler.compile(layout, id: "my-track")
        // Drivable means: grid on asphalt, gates on the ribbon, a closed loop.
        XCTAssertEqual(track.startSlots.count, 4)
        for slot in track.startSlots {
            XCTAssertEqual(track.surface(at: slot), .asphalt, "grid slot off the ribbon")
        }
        XCTAssertFalse(track.gates.isEmpty)
        XCTAssertGreaterThan(track.centerline.count, 8)
    }

    /// The code must survive the trip out and back unchanged — otherwise a
    /// design pasted into the repo isn't the one that was built.
    func testShareCodeRoundTripsTheExactLayout() throws {
        let layout = TrackLayout(pieces: square, gateSeams: [0, 2, 4, 6])
        let code = TrackCode.encode(layout)
        XCTAssertEqual(try TrackCode.decode(code), layout)
        // And the track compiled from the decoded copy matches the original's
        // geometry, which is what actually gets raced.
        let original = try PieceCompiler.compile(layout, id: "x")
        let restored = try PieceCompiler.compile(try TrackCode.decode(code), id: "x")
        XCTAssertEqual(original.centerline, restored.centerline)
        XCTAssertEqual(original.startSlots, restored.startSlots)
    }

    /// An unfinished design must not pretend to be a track — that's what grays
    /// out the custom slot in the setup picker.
    func testAnUnfinishedDesignDoesNotCompile() {
        let open = TrackLayout(pieces: [Pieces.startGrid, Pieces.straight], gateSeams: [0])
        XCTAssertNil(try? PieceCompiler.compile(open, id: "my-track"))
    }
}
