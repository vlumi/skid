import CoreGraphics
import XCTest

@testable import SkidCore
@testable import SkidKit

/// The aim-to-drive scheme: the thumb points a world direction and the
/// scheme hands it to the sim as an `aim` command (the body-flip lives in
/// the physics). Reversing is a low-speed manoeuvre only. These pin the
/// sign conventions (screen ↔ world) and the flip-vs-reverse gate.
@MainActor
final class AimControlTests: XCTestCase {
    /// A stick touched at the origin, thumb pushed to `offset`, car facing
    /// `heading` at `speed`. The thumb offset is a screen vector and the
    /// aimed heading is its angle directly (world = screen, no y-flip).
    private func aim(offset: Vec2, heading: Double, speed: Double) -> AimControlSource {
        let source = AimControlSource()
        source.bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        source.setCar(heading: heading, speed: speed)
        source.touchBegan(id: 1, at: Vec2(500, 500))
        source.touchMoved(id: 1, at: Vec2(500, 500) + offset)
        return source
    }

    private func input(offset: Vec2, heading: Double, speed: Double = 300) -> CarInput {
        aim(offset: offset, heading: heading, speed: speed).input(for: PlayerID(0), at: 0)
    }

    func testNoTouchCoasts() {
        let source = AimControlSource()
        XCTAssertEqual(source.input(for: PlayerID(0), at: 0), .coast)
    }

    func testRestingThumbInsideDeadzoneCoasts() {
        // Pushed only 5 points — under the 10-point deadzone.
        XCTAssertEqual(input(offset: Vec2(5, 0), heading: 0), .coast)
    }

    func testForwardPathEmitsTheAim() {
        // Car faces world +x (heading 0); push the thumb screen-right,
        // which is world +x too (no y-flip). Dead ahead → aim 0, full gas,
        // the steer channel untouched.
        let result = input(offset: Vec2(60, 0), heading: 0)
        XCTAssertEqual(result.aim ?? 99, 0, accuracy: 1e-9)
        XCTAssertEqual(result.steer, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(result.throttle, 0.9)
    }

    func testAimIsTheThumbAngle() {
        // Screen-down (0, +1) = world +y = heading π/2; up-screen = −π/2.
        XCTAssertEqual(input(offset: Vec2(0, 60), heading: 0).aim ?? 99, .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(
            input(offset: Vec2(0, -60), heading: 0).aim ?? 99, -.pi / 2, accuracy: 1e-9)
    }

    func testHardAimEasesTheGasButKeepsDriving() {
        // A 90° aim keeps most of the throttle — flips want gas held on.
        let result = input(offset: Vec2(0, 60), heading: 0)
        XCTAssertGreaterThan(result.throttle, 0.7)
    }

    func testAimingBehindAtSpeedFlips() {
        // Facing +x at speed, aim world −x (180° off): the body flips —
        // the aim goes through, no reverse.
        let result = input(offset: Vec2(-60, 0), heading: 0, speed: 300)
        XCTAssertEqual(abs(result.aim ?? 0), .pi, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(result.throttle, 0)
    }

    func testAimingBehindWhenSlowReverses() {
        // Same aim, but crawling: no inertia to flip with → back toward it.
        let result = input(offset: Vec2(-60, 0), heading: 0, speed: 20)
        XCTAssertNil(result.aim)
        XCTAssertLessThan(result.throttle, 0)
    }

    func testAimIsAbsoluteScreenDirectionRegardlessOfSeating() {
        // Aim points at an absolute screen spot, wherever the player sits:
        // pushing screen-down aims world +y; a car already facing +y is
        // dead ahead — aim matches, full gas.
        let result = input(offset: Vec2(0, 60), heading: .pi / 2)
        XCTAssertEqual(result.aim ?? 99, .pi / 2, accuracy: 1e-6)
        XCTAssertGreaterThan(result.throttle, 0.9)
    }
}
