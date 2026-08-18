import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The controls are always visible.** A control that only exists while touched
/// appears exactly one press too late to show a new player where to press — so a
/// stick rests at its zone's center before any touch, stays where the thumb left
/// it after a lift, and the next touch-down moves it. Lifting must also stop
/// driving: a resting stick produces `.coast`, nothing else.
@MainActor
final class RestingControlTests: XCTestCase {
    private let bounds = Rect(x: 0, y: 0, width: 1000, height: 1000)

    func testAStickRestsAtItsZoneCenterBeforeAnyTouch() {
        XCTAssertNil(VirtualDPadControlSource().displayOrigin, "no zone yet, nowhere to rest")
        XCTAssertNil(AimControlSource().displayOrigin, "no zone yet, nowhere to rest")
        let pad = VirtualDPadControlSource()
        pad.bounds = bounds
        XCTAssertEqual(pad.displayOrigin, bounds.center)
        let aim = AimControlSource()
        aim.bounds = bounds
        XCTAssertEqual(aim.displayOrigin, bounds.center)
    }

    func testAStickStaysWhereTheThumbLeftIt() {
        let pad = VirtualDPadControlSource()
        pad.bounds = bounds
        pad.touchBegan(id: 1, at: Vec2(300, 700))
        let landed = pad.origin
        pad.touchMoved(id: 1, at: Vec2(320, 650))
        pad.touchEnded(id: 1)
        XCTAssertFalse(pad.touching)
        XCTAssertEqual(pad.displayOrigin, landed, "the pad snapped away on lift")
        XCTAssertEqual(pad.knob, .zero)

        let aim = AimControlSource()
        aim.bounds = bounds
        aim.touchBegan(id: 2, at: Vec2(600, 400))
        let aimLanded = aim.origin
        aim.touchEnded(id: 2)
        XCTAssertEqual(aim.displayOrigin, aimLanded, "the stick snapped away on lift")
    }

    /// A resting stick must not drive: after the lift, whatever the knob was, the
    /// input is exactly `.coast`.
    func testARestingStickCoasts() {
        let pad = VirtualDPadControlSource()
        pad.bounds = bounds
        pad.touchBegan(id: 1, at: Vec2(500, 500))
        pad.touchMoved(id: 1, at: Vec2(500, 200))  // full gas
        pad.touchEnded(id: 1)
        XCTAssertEqual(pad.input(for: PlayerID(0), at: 0), .coast)

        let aim = AimControlSource()
        aim.bounds = bounds
        aim.touchBegan(id: 2, at: Vec2(500, 500))
        aim.touchMoved(id: 2, at: Vec2(700, 500))
        aim.touchEnded(id: 2)
        XCTAssertEqual(aim.input(for: PlayerID(0), at: 0), .coast)
    }

    /// The next touch-down MOVES the stick — it does not resume at the old spot.
    func testTheNextTouchMovesTheStick() {
        let pad = VirtualDPadControlSource()
        pad.bounds = bounds
        pad.touchBegan(id: 1, at: Vec2(300, 700))
        pad.touchEnded(id: 1)
        pad.touchBegan(id: 3, at: Vec2(800, 300))
        XCTAssertEqual(pad.origin, Vec2(800, 300))
        XCTAssertTrue(pad.touching)
    }

    /// `releaseAll` (race reset, scheme switch) still resets fully — the resting
    /// spot belongs to a race in progress, not to the next one.
    func testReleaseAllResetsTheRestingSpot() {
        let aim = AimControlSource()
        aim.bounds = bounds
        aim.touchBegan(id: 1, at: Vec2(300, 700))
        aim.touchEnded(id: 1)
        aim.releaseAll()
        XCTAssertEqual(aim.displayOrigin, bounds.center)
    }
}
