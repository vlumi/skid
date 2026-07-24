import XCTest

@testable import SkidCore

/// Piece segment geometry — arcs especially — must land on exact coordinates
/// and match hand-computed endpoints, so the walk and closure stay exact.
final class PieceGeometryTests: XCTestCase {
    private func exit(_ seg: Piece.Segment, from: PiecePose = .origin) -> PiecePose {
        seg.exit(from: from)
    }

    func testLeft90FromEast() {
        // r=100, left 90°: centre (0,100), exit (100,100) heading north.
        let e = exit(.arc(radius: 100, eighths: 2, left: true))
        XCTAssertEqual(e.position, CoordPoint(100, 100))
        XCTAssertEqual(e.heading, Heading(2))  // north
    }

    func testRight90FromEast() {
        // r=100, right 90°: centre (0,-100), exit (100,-100) heading south.
        let e = exit(.arc(radius: 100, eighths: 2, left: false))
        XCTAssertEqual(e.position, CoordPoint(100, -100))
        XCTAssertEqual(e.heading, Heading(6))  // south
    }

    func testLeft45FromEastLandsExactDiagonal() {
        // r=100, left 45°: exit heading NE; position uses √2/2 exactly.
        let e = exit(.arc(radius: 100, eighths: 1, left: true))
        XCTAssertEqual(e.heading, Heading(1))  // NE
        // centre (0,100); radial centre→entry = south (heading 6), swept left
        // 45° → SE (heading 7); exit = (0,100) + 100·SE-unit.
        // SE unit = (√2/2, -√2/2) = Coord(a:0,b:1),(a:0,b:-1).
        XCTAssertEqual(e.position.x, Coord(a: 0, b: 100))  // 100·√2/2
        XCTAssertEqual(e.position.y, Coord(a: 200, b: -100))  // 100 − 100·√2/2
    }

    func testTwo45ArcsEqualOne90() {
        // Composing two left-45 arcs should reach the same pose as one left-90
        // of the same radius — exact.
        let one90 = exit(.arc(radius: 160, eighths: 2, left: true))
        let first45 = exit(.arc(radius: 160, eighths: 1, left: true))
        let two45 = exit(.arc(radius: 160, eighths: 1, left: true), from: first45)
        XCTAssertEqual(two45.position, one90.position)
        XCTAssertEqual(two45.heading, one90.heading)
    }

    func testHairpin180IsTwo90s() {
        // A 180° left turn (4 eighths) reverses heading and offsets by 2r
        // sideways. From east at origin: exit heading west, position (0, 2r).
        let e = exit(.arc(radius: 60, eighths: 4, left: true))
        XCTAssertEqual(e.heading, Heading(4))  // west
        XCTAssertEqual(e.position, CoordPoint(0, 120))
    }

    func testLeftThenRightIsAnSCurve() {
        // Left 90 then right 90 (an S): net heading unchanged (east). Each
        // 90° arc advances +r forward and +r sideways, so the S climbs 2r up
        // and runs 2r forward: (200, 200) for r=100.
        let l = exit(.arc(radius: 100, eighths: 2, left: true))
        let s = exit(.arc(radius: 100, eighths: 2, left: false), from: l)
        XCTAssertEqual(s.heading, .east)
        XCTAssertEqual(s.position, CoordPoint(200, 200))
    }
}
