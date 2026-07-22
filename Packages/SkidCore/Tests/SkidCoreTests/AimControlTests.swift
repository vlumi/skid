import CoreGraphics
import XCTest

@testable import SkidCore
@testable import SkidKit

/// The aim-to-drive scheme: the thumb points a world direction, the car
/// steers toward it and reverses when it's behind. These pin the sign
/// conventions (screen ↔ world) and the reverse threshold.
@MainActor
final class AimControlTests: XCTestCase {
    /// A stick touched at the origin, thumb pushed to `offset`, car facing
    /// `heading`. The thumb offset is a screen vector and the aimed heading
    /// is its angle directly (world = screen, no y-flip).
    private func aim(offset: Vec2, heading: Double) -> AimControlSource {
        let source = AimControlSource()
        source.bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        source.setCarHeading(heading)
        source.touchBegan(id: 1, at: Vec2(500, 500))
        source.touchMoved(id: 1, at: Vec2(500, 500) + offset)
        return source
    }

    private func input(offset: Vec2, heading: Double) -> CarInput {
        aim(offset: offset, heading: heading).input(for: PlayerID(0), at: 0)
    }

    func testNoTouchCoasts() {
        let source = AimControlSource()
        XCTAssertEqual(source.input(for: PlayerID(0), at: 0), .coast)
    }

    func testRestingThumbInsideDeadzoneCoasts() {
        // Pushed only 5 points — under the 10-point deadzone.
        XCTAssertEqual(input(offset: Vec2(5, 0), heading: 0), .coast)
    }

    func testAimingWhereYouAlreadyFaceGoesStraight() {
        // Car faces world +x (heading 0); push the thumb screen-right,
        // which is world +x too (no y-flip). Dead ahead → full gas, no steer.
        let result = input(offset: Vec2(60, 0), heading: 0)
        XCTAssertEqual(result.steer, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(result.throttle, 0.9)
    }

    func testAimingRightOfHeadingSteersRight() {
        // Facing +x, aim down-screen (world +y). In math coords that's a
        // positive turn → steer right (positive), forward.
        let result = input(offset: Vec2(0, 60), heading: 0)
        XCTAssertGreaterThan(result.steer, 0.5)
        XCTAssertGreaterThan(result.throttle, 0)
    }

    func testAimingLeftOfHeadingSteersLeft() {
        // Facing +x, aim up-screen (world −y) → negative turn → steer left.
        let result = input(offset: Vec2(0, -60), heading: 0)
        XCTAssertLessThan(result.steer, -0.5)
        XCTAssertGreaterThan(result.throttle, 0)
    }

    func testAimingBehindReverses() {
        // Facing +x, aim screen-left (world −x): 180° off → reverse.
        let result = input(offset: Vec2(-60, 0), heading: 0)
        XCTAssertLessThan(result.throttle, 0)
    }

    func testJustInsideThresholdStillDrivesForward() {
        // ~90° off (aim straight down while facing +x) is within the ~120°
        // reverse threshold → still forward, hard steer.
        let result = input(offset: Vec2(0, 60), heading: 0)
        XCTAssertGreaterThan(result.throttle, 0)
    }

    func testAimIsAbsoluteScreenDirectionRegardlessOfSeating() {
        // Aim points at an absolute screen spot, wherever the player sits:
        // pushing screen-down (0, +1) aims at world +y. A car already
        // facing world +y (heading π/2) is dead ahead → straight, full gas.
        let result = input(offset: Vec2(0, 60), heading: .pi / 2)
        XCTAssertEqual(result.steer, 0, accuracy: 1e-6)
        XCTAssertGreaterThan(result.throttle, 0.9)
    }
}
