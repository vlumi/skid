import XCTest

@testable import SkidCore

/// **The ground a layout covers**, which the editor's canvas box, its
/// out-of-room hint and its centering all key off. They were three separate
/// transcriptions of the same arithmetic; now they share one, so it needs cover
/// of its own — nothing else in the suite fails when the padding is wrong.
final class FootprintTests: XCTestCase {
    /// A 2U straight east from the origin: 240 units long, no width of its own
    /// (the footprint measures the CENTERLINE).
    private func straightWalk() -> WalkResult {
        TrackLayout(pieces: [PieceCatalog.ID.straight]).walk()
    }

    func testUnpaddedFootprintIsTheCenterlineExtent() throws {
        let box = try XCTUnwrap(straightWalk().footprint())
        XCTAssertEqual(box.width, 240, accuracy: 0.001)
        XCTAssertEqual(box.height, 0, accuracy: 0.001)
        XCTAssertEqual(box.minX, 0, accuracy: 0.001)
    }

    /// Padding applies to **both** sides of each axis. A one-sided version
    /// passes every other test in the suite, so it is pinned here.
    func testPaddingGrowsBothSidesOfEachAxis() throws {
        let box = try XCTUnwrap(straightWalk().footprint(padding: 10))
        XCTAssertEqual(box.width, 260, accuracy: 0.001)  // 240 + 2 × 10
        XCTAssertEqual(box.height, 20, accuracy: 0.001)  // 0 + 2 × 10
        XCTAssertEqual(box.minX, -10, accuracy: 0.001)
        XCTAssertEqual(box.minY, -10, accuracy: 0.001)
    }

    /// The padded variant is what the validator measures against the canvas:
    /// the road's half-width on every side.
    func testPaddedFootprintUsesTheRoadHalfWidth() throws {
        let half = Double(PieceCatalog.width) / 2
        let box = try XCTUnwrap(straightWalk().paddedFootprint())
        XCTAssertEqual(box.width, 240 + 2 * half, accuracy: 0.001)
        XCTAssertEqual(box.height, 2 * half, accuracy: 0.001)
    }

    /// The center is what centering shifts onto the canvas middle.
    func testCenterIsTheMiddleOfTheExtent() throws {
        let box = try XCTUnwrap(straightWalk().footprint())
        XCTAssertEqual(box.center.x, 120, accuracy: 0.001)
        XCTAssertEqual(box.center.y, 0, accuracy: 0.001)
    }

    func testAnEmptyWalkHasNoFootprint() {
        let empty = WalkResult(placed: [], openEnds: [], failure: .emptyLayout)
        XCTAssertNil(empty.footprint())
    }
}
