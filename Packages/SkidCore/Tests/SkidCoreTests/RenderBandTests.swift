import XCTest

@testable import SkidCore
@testable import SkidKit

/// What belongs to which height band. The race view draws the ground, then the
/// cars, then the bridge over them — so anything painted in the wrong band
/// shows through the deck.
final class RenderBandTests: XCTestCase {
    /// The two bands the race view draws, split at half a level.
    private let ground = -1.0...0.5
    private let elevated = 0.5...2.0

    /// **The start line and grid are paint on the start piece's own road**, so
    /// they draw in that piece's band and no other. Both ends have to be inside
    /// it: testing only the exit let a ground-level start line paint during the
    /// elevated pass, showing through a bridge that crosses over it.
    func testTheStartPieceBelongsToExactlyOneBand() throws {
        for id in ["small", "oval", "eight"] {
            let layout = try XCTUnwrap(TrackLibrary.layout(id: id))
            let start = try XCTUnwrap(
                layout.walk().placed.first { $0.id == PieceCatalog.startPieceID })
            let inGround =
                ground.contains(start.entryHeight) && ground.contains(start.exitHeight)
            let inElevated =
                elevated.contains(start.entryHeight) && elevated.contains(start.exitHeight)
            XCTAssertNotEqual(
                inGround, inElevated,
                "\(id): the start piece must draw in exactly one band")
        }
    }

    /// A crossing exists on the eight at both heights — the case where a
    /// misbanded start line would be visible — so the fixture really exercises
    /// the rule rather than passing for lack of a bridge.
    func testTheEightHasRoadAtBothBands() throws {
        let layout = try XCTUnwrap(TrackLibrary.layout(id: "eight"))
        let placed = layout.walk().placed
        XCTAssertTrue(placed.contains { ground.contains($0.entryHeight) })
        XCTAssertTrue(placed.contains { elevated.contains($0.exitHeight) })
    }
}
