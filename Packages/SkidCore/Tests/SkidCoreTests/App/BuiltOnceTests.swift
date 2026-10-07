import Foundation
import XCTest

@testable import SkidKit

/// `GameView`'s games live in this box because `@State` evaluates its initial
/// value on every init of the view — the box must build lazily, and once.
@MainActor
final class BuiltOnceTests: XCTestCase {
    func testBuildsOnFirstReadAndOnlyThen() {
        var built = 0
        let box = BuiltOnce { () -> NSObject in
            built += 1
            return NSObject()
        }
        XCTAssertEqual(built, 0, "a box that is thrown away must not have built anything")
        let first = box.value
        XCTAssertTrue(box.value === first, "a second read built a second instance")
        XCTAssertEqual(built, 1)
    }
}
