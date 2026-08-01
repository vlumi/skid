import XCTest

@testable import SkidCore

/// Rotating a whole layout, exactly.
///
/// This exists because rotation is the one operation that could quietly destroy
/// the piece model's core guarantee: coordinates live in the ring `(a + b√2)/2`
/// so that loop closure is integer equality with no epsilon. A rotation that
/// rounded — even by one ULP — would turn "the ring closes" into "the ring
/// almost closes", which is unfixable downstream.
final class CoordRotationTests: XCTestCase {
    /// √2⁄2 scaling is a swap-and-halve, and matches the real arithmetic.
    func testHalfSqrt2MatchesRealArithmetic() {
        for value in [Coord(120), Coord(240), Coord(a: 0, b: 240), Coord(a: 120, b: 60)] {
            XCTAssertTrue(value.timesHalfSqrt2IsExact, "\(value) should scale exactly")
            XCTAssertEqual(
                value.timesHalfSqrt2.value, value.value * 2.0.squareRoot() / 2, accuracy: 1e-9)
        }
    }

    /// An odd rational part can't halve, and the flag says so rather than
    /// silently truncating.
    func testHalfSqrt2ReportsInexactness() {
        XCTAssertFalse(Coord(a: 121, b: 0).timesHalfSqrt2IsExact)
    }

    /// Every 45° step matches a real rotation of the same point.
    func testRotationMatchesRealRotation() {
        let point = CoordPoint(x: Coord(240), y: Coord(120))
        for eighths in 0..<8 {
            let rotated = point.rotated(eighths: eighths)
            let angle = Double(eighths) * .pi / 4
            let expectedX = point.x.value * cos(angle) - point.y.value * sin(angle)
            let expectedY = point.x.value * sin(angle) + point.y.value * cos(angle)
            XCTAssertEqual(rotated.x.value, expectedX, accuracy: 1e-9, "x at \(eighths)/8")
            XCTAssertEqual(rotated.y.value, expectedY, accuracy: 1e-9, "y at \(eighths)/8")
        }
    }

    /// **The exactness guarantee**: eight 45° steps return the ORIGINAL integer
    /// pair, not merely something close to it. Exact `Equatable`, no accuracy
    /// argument — that's the whole point of the ring.
    func testEightStepsReturnExactlyHome() {
        let points = [
            CoordPoint(240, 120), CoordPoint(x: Coord(a: 0, b: 240), y: Coord(a: 0, b: 240)),
            CoordPoint(-480, 360),
        ]
        for point in points {
            var turned = point
            for _ in 0..<8 { turned = turned.rotated(eighths: 1) }
            XCTAssertEqual(turned, point, "\(point) must come home exactly")
        }
    }

    /// Quarter turns are pure swaps, so they're exact for ANY point — including
    /// ones a 45° step would have to refuse.
    func testQuarterTurnsAreAlwaysExact() {
        let awkward = CoordPoint(x: Coord(a: 121, b: 0), y: Coord(a: 3, b: 1))
        var turned = awkward
        for _ in 0..<4 { turned = turned.rotated(eighths: 2) }
        XCTAssertEqual(turned, awkward)
    }

    /// A layout rotated 45° is the SAME TRACK: same piece count, still closed,
    /// and every piece's spacing preserved. (Turning a valid ring must not
    /// invalidate it.)
    func testRotatingALayoutKeepsItClosedAndCongruent() {
        let pieces: [PieceID] = [
            PieceCatalog.ID.startGrid, PieceCatalog.ID.curve90MediumLeft,
            PieceCatalog.ID.straight, PieceCatalog.ID.curve90MediumLeft,
            PieceCatalog.ID.straight, PieceCatalog.ID.curve90MediumLeft,
            PieceCatalog.ID.straight, PieceCatalog.ID.curve90MediumLeft,
        ]
        let layout = TrackLayout(pieces: pieces)
        let before = layout.walk()
        XCTAssertTrue(before.openEnds.isEmpty, "the fixture must be a closed ring")

        var rotated = layout
        rotated.origin = PiecePose(
            position: layout.origin.position.rotated(eighths: 1),
            heading: layout.origin.heading.turnedLeft(1))
        let after = rotated.walk()

        XCTAssertNil(after.failure)
        XCTAssertTrue(after.openEnds.isEmpty, "rotating must not break loop closure")
        XCTAssertEqual(after.placed.count, before.placed.count)

        // Congruence: consecutive entry points keep their spacing exactly.
        for index in 1..<before.placed.count {
            let originalStep =
                (before.placed[index].entry.position.vec2
                - before.placed[index - 1].entry.position.vec2).length
            let rotatedStep =
                (after.placed[index].entry.position.vec2
                - after.placed[index - 1].entry.position.vec2).length
            XCTAssertEqual(rotatedStep, originalStep, accuracy: 1e-6, "piece \(index) spacing")
        }
    }

    /// Rotating **trades one axis for the other** — it does not simply shrink
    /// the bounding box, and the editor's advice must not claim otherwise.
    ///
    /// Measured on a diagonal track: 1158 × 1158 unrotated becomes 1539 × 480 at
    /// 45°. The area barely moves; what changes is the *shape* of the box. That's
    /// why rotating can unblock a layout — one orientation may fit a
    /// non-square limit when another doesn't — and equally why it can break one:
    /// a diagonal run measuring 1428 × 1089 (fits) becomes 1779 × 240, which
    /// exceeds the 1600 width.
    func testRotatingTradesOneAxisForTheOther() {
        let layout = TrackLayout(pieces: [
            PieceCatalog.ID.startGrid, PieceCatalog.ID.curve45MediumLeft,
            PieceCatalog.ID.longStraight, PieceCatalog.ID.longStraight,
        ])

        func box(_ layout: TrackLayout, eighths: Int) -> (width: Double, height: Double) {
            var turned = layout
            turned.origin = PiecePose(
                position: layout.origin.position.rotated(eighths: eighths),
                heading: layout.origin.heading.turnedLeft(eighths))
            let points = turned.walk().placed.flatMap { $0.centerlineSamples() }
            return (
                (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0),
                (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)
            )
        }

        let square = box(layout, eighths: 0)
        let turned = box(layout, eighths: 1)
        // One axis grows while the other shrinks: a trade, not a saving.
        XCTAssertGreaterThan(turned.width, square.width, "one axis grows")
        XCTAssertLessThan(turned.height, square.height, "…while the other shrinks")
        // And the trade is lopsided enough to matter against a non-square limit
        // — which is what makes Rotate a real unblocking tool rather than a
        // cosmetic one.
        XCTAssertGreaterThan(
            max(turned.width, turned.height) / max(1, min(turned.width, turned.height)),
            max(square.width, square.height) / max(1, min(square.width, square.height)),
            "the diagonal orientation should be the more lopsided box")
    }
}
