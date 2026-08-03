import XCTest

@testable import SkidCore

/// **Holding back keeps reversing.** Reported from device: in aim mode, pushing
/// full back reverses at first and then "tries to turn around after a while",
/// and with a big turning circle that makes a sharp direction change hard.
///
/// The gate was `carSpeed < reverseBelowSpeed`, and `carSpeed` came from
/// `velocity.length` — unsigned. So a car reversing at 91 units/s looked exactly
/// like one driving forward at 91: the gate closed and the scheme handed over to
/// the body-flip. Measured before the fix: full reverse at 89, and +0.75 forward
/// throttle at 91.
///
/// A car that is already going backwards has nothing to flip, so the gate now
/// reads FORWARD speed, which is negative while reversing.
final class AimReverseTests: XCTestCase {
    private func aimingBackwards() -> AimControlSource {
        let source = AimControlSource()
        source.bounds = Rect(x: 0, y: 0, width: 1000, height: 1000)
        source.touchBegan(id: 1, at: Vec2(500, 500))
        // Car faces east; thumb held straight back (west).
        source.touchMoved(id: 1, at: Vec2(440, 500))
        return source
    }

    /// The reported bug: reversing must not give up once it gathers pace.
    func testHoldingBackKeepsReversingAtSpeed() {
        let source = aimingBackwards()
        for speed in [0.0, 40, 89, 91, 150, 300] {
            source.setCar(heading: 0, forwardSpeed: -speed, speed: speed)
            let input = source.input(for: PlayerID(0), at: 0)
            XCTAssertLessThan(
                input.throttle, 0,
                "reversing at \(Int(speed)) units/s must keep reversing, not flip")
            XCTAssertNil(input.aim, "a reversing car is not aiming")
        }
    }

    /// Driving FORWARD fast at a target behind you still flips — that is the
    /// arcade move, and the whole reason the speed gate exists.
    func testDrivingForwardFastStillFlips() {
        let source = aimingBackwards()
        source.setCar(heading: 0, forwardSpeed: 300, speed: 300)
        let input = source.input(for: PlayerID(0), at: 0)
        XCTAssertGreaterThan(input.throttle, 0, "a fast forward car flips rather than reversing")
        XCTAssertNotNil(input.aim)
    }

    /// Slow and forward is the parking-lot case: reverse toward the target.
    func testSlowAndForwardReverses() {
        let source = aimingBackwards()
        source.setCar(heading: 0, forwardSpeed: 20, speed: 20)
        XCTAssertLessThan(source.input(for: PlayerID(0), at: 0).throttle, 0)
    }

    /// Aiming ahead is unaffected: throttle forward, aim handed to the sim.
    func testAimingAheadIsUnchanged() {
        let source = AimControlSource()
        source.bounds = Rect(x: 0, y: 0, width: 1000, height: 1000)
        source.touchBegan(id: 1, at: Vec2(500, 500))
        source.touchMoved(id: 1, at: Vec2(560, 500))
        source.setCar(heading: 0, forwardSpeed: 200, speed: 200)
        let input = source.input(for: PlayerID(0), at: 0)
        XCTAssertGreaterThan(input.throttle, 0)
        XCTAssertNotNil(input.aim)
    }
}
