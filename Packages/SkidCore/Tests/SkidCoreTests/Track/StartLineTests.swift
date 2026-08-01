import XCTest

@testable import SkidCore

/// Where the start/finish line and the starting grid sit.
final class StartLineTests: XCTestCase {
    /// The start/finish line must sit at the start piece's EXIT, and the grid must
    /// run back from it onto the start piece. Both are asserted against the
    /// geometry itself rather than against remembered coordinates, so the seam
    /// renumbering can't quietly move them.
    func testFinishLineIsAtTheStartPieceExit() throws {
        for id in ["small", "oval", "eight"] {
            let track = TrackLibrary.track(id: id)
            let layout = try XCTUnwrap(track.layout)
            let walk = layout.walk()
            let startIndex = try XCTUnwrap(
                walk.placed.firstIndex { $0.id == PieceCatalog.startPieceID })
            let expected = walk.placed[startIndex].exits[0].position.vec2 + track.layoutOffset
            // The runtime convention: the LAST gate is start/finish.
            let finish = try XCTUnwrap(track.gates.last)
            let mid = Vec2((finish.a.x + finish.b.x) / 2, (finish.a.y + finish.b.y) / 2)
            XCTAssertEqual(mid.x, expected.x, accuracy: 1, "\(id): finish line x")
            XCTAssertEqual(mid.y, expected.y, accuracy: 1, "\(id): finish line y")
            // And every grid slot is on the ribbon behind it.
            for (index, slot) in track.startSlots.enumerated() {
                XCTAssertEqual(
                    track.surface(at: slot, height: 0), .asphalt,
                    "\(id): grid slot \(index) is off the ribbon")
            }
        }
    }
}
