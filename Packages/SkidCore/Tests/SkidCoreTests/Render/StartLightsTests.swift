import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The start gantry, and the one property it exists for.**
///
/// Lights replaced a mirrored "3 · 2 · 1" because a number upside down is not that
/// number — so the row has to read identically from every seat around the phone. That
/// is a property, not a look, and it is what these hold.
final class StartLightsTests: XCTestCase {
    /// **Every state is symmetric.** The reason the design works at all: a player on the
    /// far side of the table sees the same pattern, not a reversed one.
    func testEveryStateReadsTheSameUpsideDown() {
        for seconds in -1...4 {
            let lamps = StartLights.pattern(secondsRemaining: seconds)
            XCTAssertEqual(
                lamps, lamps.reversed(),
                "with \(seconds)s left the gantry is not symmetric: \(lamps)")
        }
    }

    /// **Lights fill up as the start approaches**, never down — the circuit-racing
    /// convention this is copying.
    func testLightsFillUpAsTheStartApproaches() {
        let three = StartLights.pattern(secondsRemaining: 3).filter { $0 }.count
        let two = StartLights.pattern(secondsRemaining: 2).filter { $0 }.count
        let one = StartLights.pattern(secondsRemaining: 1).filter { $0 }.count
        XCTAssertEqual(three, 2, "3s should light the outer pair")
        XCTAssertEqual(two, 4)
        XCTAssertEqual(one, StartLights.count, "the last second lights them all")
        XCTAssertLessThan(three, two)
        XCTAssertLessThan(two, one)
    }

    /// **The start is every light going out**, which is the signal itself.
    func testTheStartIsAllLightsOut() {
        XCTAssertTrue(StartLights.pattern(secondsRemaining: 0).allSatisfy { !$0 })
        XCTAssertTrue(
            StartLights.pattern(secondsRemaining: -1).allSatisfy { !$0 },
            "past the start stays dark rather than wrapping around")
    }

    /// The outermost pair lights first and the middle last, so the sequence grows inward
    /// rather than appearing all at once at the end.
    func testItFillsFromTheOutsideIn() {
        XCTAssertEqual(
            StartLights.pattern(secondsRemaining: 3), [true, false, false, false, true])
        XCTAssertEqual(
            StartLights.pattern(secondsRemaining: 2), [true, true, false, true, true])
        XCTAssertEqual(
            StartLights.pattern(secondsRemaining: 1), [true, true, true, true, true])
    }
}
