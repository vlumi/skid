import XCTest

@testable import SkidCore

/// The exact-coordinate foundation: values of the form (a + b√2)/2, closed
/// under the moves the piece walk makes, so closure is integer equality.
final class CoordTests: XCTestCase {
    private let sqrt2 = 2.0.squareRoot()

    func testValueMatchesFormula() {
        XCTAssertEqual(Coord(a: 2, b: 0).value, 1, accuracy: 1e-12)  // whole 1
        XCTAssertEqual(Coord(a: 0, b: 1).value, sqrt2 / 2, accuracy: 1e-12)
        XCTAssertEqual(Coord(3).value, 3, accuracy: 1e-12)
    }

    func testArithmeticIsExactInteger() {
        let x = Coord(a: 3, b: 5)
        let y = Coord(a: -1, b: 2)
        XCTAssertEqual(x + y, Coord(a: 2, b: 7))
        XCTAssertEqual(x - y, Coord(a: 4, b: 3))
        XCTAssertEqual(x * 3, Coord(a: 9, b: 15))
        XCTAssertEqual(-x, Coord(a: -3, b: -5))
    }

    func testHeadingWrapsAndReverses() {
        XCTAssertEqual(Heading(8), Heading.east)
        XCTAssertEqual(Heading(-1), Heading(7))
        XCTAssertEqual(Heading.east.reversed, Heading(4))
        XCTAssertEqual(Heading(2).turnedLeft(), Heading(3))
        XCTAssertEqual(Heading(2).turnedRight(2), Heading(0))
    }

    func testStraightAlongEachHeadingLandsExact() {
        // A length-100 straight from origin along every heading, then the
        // reverse straight, returns EXACTLY to origin — the closure primitive.
        for step in 0..<8 {
            let out = PiecePose(position: .zero, heading: Heading(step)).advanced(by: 100)
            let back = PiecePose(position: out.position, heading: Heading(step).reversed)
                .advanced(by: 100)
            XCTAssertEqual(back.position, .zero, "heading \(step) round trip not exact")
        }
    }

    func testDiagonalStraightMatchesFloatGeometry() {
        // NE by 100: each axis should be 100·√2/2, exactly represented.
        let p = PiecePose(position: .zero, heading: Heading(1)).advanced(by: 100)
        XCTAssertEqual(p.position.x, Coord(a: 0, b: 100))
        XCTAssertEqual(p.position.vec2.x, 100 * sqrt2 / 2, accuracy: 1e-9)
        XCTAssertEqual(p.position.vec2.y, 100 * sqrt2 / 2, accuracy: 1e-9)
    }

    func testEightDiagonalStraightsCloseIntoAnOctagon() {
        // Walk one straight along each of the 8 headings from origin; summing
        // the 8 unit steps must cancel to exactly zero (opposite pairs).
        var p = CoordPoint.zero
        for step in 0..<8 {
            p = p + Heading(step).unitStep * 100
        }
        XCTAssertEqual(p, .zero)
    }
}
