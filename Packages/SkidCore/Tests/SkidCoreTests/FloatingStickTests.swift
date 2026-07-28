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

    /// **A finger outside the zone AIMS the stick.** The origin can only move
    /// inside the player's zone, but the finger can be beyond it — the inset
    /// around a notch is untouchable screen, not untouchable finger. When the
    /// clamp bites, the origin holds and the knob points at the finger at full
    /// deflection, so steering keeps its full range.
    func testAnOutOfZoneFingerAimsTheStick() {
        let zone = CGRect(x: 0, y: 59, width: 390, height: 300)
        let radius = 48.0
        let origin = Vec2(200, 120)
        func bearing(_ dx: Double) -> Double {
            let (o, knob) = floatingStick(
                origin: origin, finger: Vec2(200 + dx, 20), radius: radius, bounds: zone)
            XCTAssertEqual(o.x, origin.x, accuracy: 0.001, "the origin must hold")
            XCTAssertEqual(o.y, origin.y, accuracy: 0.001, "the origin must hold")
            XCTAssertEqual(knob.length, radius, accuracy: 0.001, "full deflection")
            return atan2(knob.y, knob.x) * 180 / .pi
        }
        // Straight above: dead ahead. Then sideways movement must actually turn
        // it — a trailing origin swung only 20° over this range, because it
        // slid along the clamp edge while the perpendicular offset stayed
        // pinned ("pulling down is easy, turning nearly impossible").
        XCTAssertEqual(bearing(0), -90, accuracy: 0.5)
        XCTAssertGreaterThan(
            bearing(120) - bearing(0), 45,
            "moving the finger 120pt sideways must swing the stick well past 20°")
    }

    /// Aiming applies only when the clamp actually bites: a finger inside the
    /// zone still drags the origin, so the rim behaviour the scheme is built on
    /// is unchanged.
    func testAFingerInsideTheZoneStillDragsTheOrigin() {
        let zone = CGRect(x: 0, y: 0, width: 390, height: 600)
        let origin = Vec2(200, 300)
        let (moved, knob) = floatingStick(
            origin: origin, finger: Vec2(200, 420), radius: 48, bounds: zone)
        XCTAssertEqual(moved.y, 372, accuracy: 0.001, "origin trails 48 behind the finger")
        XCTAssertEqual(knob.length, 48, accuracy: 0.001)
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
