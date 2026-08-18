import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The car's silhouette points forward by itself.**
///
/// The tapered nose replaced the white lamp dots as the body's own facing cue, and
/// unlike a tone it spends nothing from the palette's separation budget. These pin
/// the drawn shape — a rectangle here would pass a "has a path" test while reading
/// symmetric on screen, which is exactly the regression that matters.
final class CarBodyTests: XCTestCase {
    private let length = CarGeometry.length
    private let bodyHeight = CarGeometry.width * 0.62

    /// The taper is subtle by design: clearly narrower than the tail, nowhere near
    /// a wedge.
    func testTheTaperIsSubtle() {
        XCTAssertLessThan(CarBody.noseFraction, 0.9)
        XCTAssertGreaterThan(CarBody.noseFraction, 0.6)
    }

    /// Rear corners full width, nose corners pulled in — asked of the PATH, the
    /// thing actually filled, not of the constants.
    func testTheNoseIsNarrowerThanTheTail() {
        let path = CarBody.path(length: length, bodyHeight: bodyHeight)
        let shoulder = bodyHeight / 2 * 0.9  // just inside the rear half-width
        XCTAssertTrue(
            path.contains(CGPoint(x: -length / 2 + 0.1, y: shoulder)),
            "the tail lost its full width")
        XCTAssertFalse(
            path.contains(CGPoint(x: length / 2 - 0.1, y: shoulder)),
            "the nose is as wide as the tail — the silhouette no longer points")
        // And the body still spans its full box: no accidental shrink. (Loose
        // accuracy: Path.boundingRect rounds through single precision.)
        let box = path.boundingRect
        XCTAssertEqual(box.width, length, accuracy: 1e-3)
        XCTAssertEqual(box.height, bodyHeight, accuracy: 1e-3)
    }
}
