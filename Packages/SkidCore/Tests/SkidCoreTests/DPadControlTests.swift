import CoreGraphics
import XCTest

@testable import SkidCore
@testable import SkidKit

/// The Pro d-pad scheme: the pad materializes where the thumb lands and STAYS
/// there for the touch's whole life (gas / brake / left / right keep fixed
/// screen positions). These pin the fixed-origin behaviour — the fix for the
/// origin creeping upward when gas is held without braking.
@MainActor
final class DPadControlTests: XCTestCase {
    private let radius = 48.0

    private func pad() -> VirtualDPadControlSource {
        let source = VirtualDPadControlSource()
        source.bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        source.touchBegan(id: 1, at: Vec2(500, 500))
        return source
    }

    func testOriginStaysPutWhenDraggedPastTheRim() {
        let source = pad()
        let origin = source.origin
        // Push the thumb far past the rim (toward screen-up = throttle).
        source.touchMoved(id: 1, at: Vec2(500, 500) - Vec2(0, 300))
        // The origin has NOT moved (unlike Casual's trailing stick), so the
        // pad doesn't creep up the screen under sustained gas.
        XCTAssertEqual(source.origin, origin)
        // The knob clamps to the rim.
        XCTAssertEqual(source.knob.length, radius, accuracy: 1e-9)
    }

    func testHeldGasThenReleaseReturnsToRest() {
        // The reported bug: hold gas (never brake) and the pad used to creep
        // upward and never come back. With a fixed origin, easing the thumb
        // back toward the origin drops throttle smoothly to zero.
        let source = pad()
        source.touchMoved(id: 1, at: Vec2(500, 500) - Vec2(0, 300))  // full gas
        XCTAssertGreaterThan(source.input(for: PlayerID(0), at: 0).throttle, 0.9)
        source.touchMoved(id: 1, at: Vec2(500, 500))  // thumb back to origin
        XCTAssertEqual(source.input(for: PlayerID(0), at: 0).throttle, 0, accuracy: 1e-9)
    }

    func testAxesMapThrottleUpAndSteerSideways() {
        let source = pad()
        source.levels = nil  // analog, no quantization steps
        source.expo = 1  // linear, so the value is predictable
        // Straight up = throttle, no steer.
        source.touchMoved(id: 1, at: Vec2(500, 500) - Vec2(0, radius))
        let up = source.input(for: PlayerID(0), at: 0)
        XCTAssertGreaterThan(up.throttle, 0.9)
        XCTAssertEqual(up.steer, 0, accuracy: 1e-9)
        // Pull back = brake / reverse (negative throttle).
        source.touchMoved(id: 1, at: Vec2(500, 500) + Vec2(0, radius))
        XCTAssertLessThan(source.input(for: PlayerID(0), at: 0).throttle, -0.9)
        // Sideways = steer, no throttle.
        source.touchMoved(id: 1, at: Vec2(500, 500) + Vec2(radius, 0))
        let side = source.input(for: PlayerID(0), at: 0)
        XCTAssertGreaterThan(side.steer, 0.9)
        XCTAssertEqual(side.throttle, 0, accuracy: 1e-9)
    }
}
