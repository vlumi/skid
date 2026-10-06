import XCTest

@testable import SkidCore

/// **Arrow keys over any menu layout**, as the menus are actually built: rows
/// of pills, full-width buttons, and both mixed.
final class SpatialFocusTests: XCTestCase {
    private func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Rect {
        Rect(x: x, y: y, width: w, height: h)
    }

    /// The setup screen's shape: a row of three pills, a full-width button
    /// below, and a second row of three below that.
    private lazy var screen: [Rect] = [
        r(40, 0, 100, 40), r(160, 0, 100, 40), r(280, 0, 100, 40),  // 0 1 2
        r(20, 80, 380, 60),  // 3: the track row
        r(40, 180, 100, 40), r(160, 180, 100, 40), r(280, 180, 100, 40),  // 4 5 6
    ]

    private func move(_ from: Int?, _ direction: FocusDirection) -> Int? {
        SpatialFocus.next(from: from.map { screen[$0] }, among: screen, direction: direction)
    }

    func testTheFirstPressPicksTheReadingOrderFirst() {
        for direction in FocusDirection.allCases {
            XCTAssertEqual(move(nil, direction), 0, "\(direction)")
        }
        XCTAssertNil(SpatialFocus.next(from: nil, among: [], direction: .down))
    }

    func testLeftAndRightWalkARow() {
        XCTAssertEqual(move(0, .right), 1)
        XCTAssertEqual(move(1, .right), 2)
        XCTAssertNil(move(2, .right), "walked off the end")
        XCTAssertEqual(move(2, .left), 1)
    }

    /// Down from any pill of the top row lands on the wide button below it,
    /// and down again lands on the pill under where you came from — straight
    /// columns survive a full-width row in between.
    func testUpAndDownCrossAFullWidthRow() {
        for pill in 0...2 { XCTAssertEqual(move(pill, .down), 3, "pill \(pill)") }
        XCTAssertEqual(move(3, .down), 5, "down from the wide row should take the centred pill")
        XCTAssertEqual(move(6, .up), 3)
        XCTAssertNil(move(0, .up), "moved up from the top row")
    }

    /// Something straight ahead wins over something just as near off to the
    /// side; a near row only slightly off to the side beats a far one that
    /// lines up; but a button FAR off to the side loses to the one directly
    /// below, however much further down that is — it is what "down" means.
    func testOverlapPreferredButDistanceStillCounts() {
        let nearby = [
            r(300, 0, 80, 40),  // 0: current
            r(180, 60, 100, 40),  // 1: next row, 20 pt off to the left
            r(0, 400, 400, 40),  // 2: a full-width row far below
        ]
        XCTAssertEqual(
            SpatialFocus.next(from: nearby[0], among: nearby, direction: .down), 1,
            "skipped a near row for a far aligned one")
        let farOff = [r(300, 0, 80, 40), r(0, 60, 120, 40), r(0, 400, 400, 40)]
        XCTAssertEqual(
            SpatialFocus.next(from: farOff[0], among: farOff, direction: .down), 2,
            "a button 180 pt off to the side beat the one directly below")
        let aligned = [r(300, 0, 80, 40), r(0, 60, 120, 40), r(280, 70, 120, 40)]
        XCTAssertEqual(
            SpatialFocus.next(from: aligned[0], among: aligned, direction: .down), 2,
            "an aligned button at the same distance should win")
    }
}
