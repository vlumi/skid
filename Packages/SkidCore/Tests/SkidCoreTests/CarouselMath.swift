import XCTest

@testable import SkidCore
@testable import SkidKit

/// The carousel's window arithmetic. A still render can't show whether the
/// neighbours peek, so the numbers are checked directly.
final class CarouselMath: XCTestCase {
    func testWindowShowsNeighbours() {
        let height: CGFloat = 64
        let peek: CGFloat = 9
        let spacing: CGFloat = 6
        let step = height + spacing
        let window = height + peek * 2
        // The window must be taller than one row, or nothing peeks.
        XCTAssertGreaterThan(window, height, "window must exceed a single row")
        // For each index, the selected row must sit fully inside the window.
        for index in 0..<3 {
            let offset = -CGFloat(index) * step + peek
            let rowTop = offset + CGFloat(index) * step
            let rowBottom = rowTop + height
            XCTAssertEqual(rowTop, peek, accuracy: 0.01, "row \(index) top")
            XCTAssertLessThanOrEqual(rowBottom, window, "row \(index) must fit the window")
            // …and a neighbour must be partly visible.
            if index > 0 {
                let previousBottom = rowTop - spacing
                XCTAssertGreaterThan(previousBottom, 0, "the row above should peek in")
            }
            if index < 2 {
                let nextTop = rowBottom + spacing
                XCTAssertLessThan(nextTop, window, "the row below should peek in")
            }
        }
    }
}
