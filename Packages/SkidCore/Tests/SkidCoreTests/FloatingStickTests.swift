import CoreGraphics
import XCTest

@testable import SkidCore
@testable import SkidKit

/// The floating-stick re-centering: within the radius the origin holds;
/// dragging past the rim trails the origin along so you can swing extreme
/// to extreme without lifting.
final class FloatingStickTests: XCTestCase {
    private let radius = 48.0

    func testWithinRadiusOriginHolds() {
        let origin = Vec2(500, 500)
        let (newOrigin, knob) = floatingStick(
            origin: origin, finger: Vec2(520, 500), radius: radius, bounds: nil)
        XCTAssertEqual(newOrigin, origin)  // unchanged
        XCTAssertEqual(knob, Vec2(20, 0))  // knob just follows
    }

    func testPastRimDragsOriginAndPinsKnob() {
        let origin = Vec2(500, 500)
        // Finger 100 past origin, radius 48 → origin trails to 48 behind.
        let (newOrigin, knob) = floatingStick(
            origin: origin, finger: Vec2(600, 500), radius: radius, bounds: nil)
        XCTAssertEqual(newOrigin, Vec2(600 - radius, 500))  // trailed along
        XCTAssertEqual(knob.length, radius, accuracy: 1e-9)  // pinned at full
        XCTAssertEqual(knob, Vec2(radius, 0))
    }

    func testSwingBackImmediatelyUnMaxes() {
        // Drag to the right rim, then push left: because the origin trailed,
        // a small leftward move drops well below full deflection at once —
        // the whole point (you can flip sides without lifting).
        var origin = Vec2(500, 500)
        (origin, _) = floatingStick(
            origin: origin, finger: Vec2(700, 500), radius: radius, bounds: nil)
        // Now finger comes back to just left of the trailed origin.
        let (_, knob) = floatingStick(
            origin: origin, finger: origin - Vec2(10, 0), radius: radius, bounds: nil)
        XCTAssertEqual(knob, Vec2(-10, 0))  // instantly un-maxed, pointing left
    }

    func testTrailingOriginStaysInsideBounds() {
        // A zone with little room: dragging far right can't push the stick's
        // travel circle out of the zone — the origin re-clamps.
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let (newOrigin, _) = floatingStick(
            origin: Vec2(200, 200), finger: Vec2(10000, 200), radius: radius, bounds: bounds)
        let margin = radius + 18
        XCTAssertLessThanOrEqual(newOrigin.x, bounds.maxX - margin + 1e-9)
        XCTAssertGreaterThanOrEqual(newOrigin.x, bounds.minX + margin - 1e-9)
    }
}
