import XCTest

@testable import SkidCore

/// **The rear 60° either side of the tail reverses, and keeps reversing.**
///
/// Aim mode splits the stick into a forward arc (±120° of the nose, chased
/// forwards by the sim's body-flip) and a rear wedge that backs up. Two device
/// reports shaped these tests: "it tries to turn around after a while", then
/// "it still tries to flip from reversing almost immediately".
///
/// Both had the same root cause — the reverse steered itself out of reverse.
/// The gate asks whether the target is behind the car's HEADING, and the
/// maneuver swings the tail toward the thumb, which rotates that same heading
/// until the target is no longer behind. Measured on a flat road, a steady
/// thumb held 170° off the nose reversed for 41 ticks and came to rest heading
/// 170° — a completed three-point turn — and 130° gave up after 12.
final class AimReverseTests: XCTestCase {
    /// A flat, wide road: only the controls are under test.
    private func flatTrack() -> Track {
        Track(
            centerline: [Vec2(-9000, 0), Vec2(9000, 0)], width: 4000,
            startSlots: [Vec2(0, 0)], size: Vec2(20000, 9000))
    }

    /// Hold a steady thumb at `aimDegrees` off the nose for `ticks`.
    private func hold(
        aimDegrees: Double, ticks: Int = 150
    ) -> (reverseTicks: Int, everFlipped: Bool, endHeadingDegrees: Double) {
        var race = Race(
            track: flatTrack(), players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.heading = 0
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        let aim = aimDegrees * .pi / 180
        source.touchMoved(id: TouchID(1), at: Vec2(500 + cos(aim) * 80, 500 + sin(aim) * 80))

        var reverseTicks = 0
        var everFlipped = false
        for tick in 0..<ticks {
            let car = race.cars[0].state
            source.setCar(
                heading: car.heading, forwardSpeed: car.velocity.dot(car.forward),
                speed: car.velocity.length)
            let input = source.input(for: PlayerID(0), at: Tick(tick))
            // The reverse maneuver drives the wheel directly; the forward
            // scheme hands an `aim` to the sim instead.
            if input.aim == nil { reverseTicks += 1 } else { everFlipped = true }
            race.advance(inputs: [PlayerID(0): input])
        }
        return (reverseTicks, everFlipped, race.cars[0].state.heading * 180 / .pi)
    }

    /// The report, as a test: a thumb held in the wedge never hands over.
    ///
    /// 170°, not 180° — a finger cannot hold a mathematically perfect reverse,
    /// and 180° passed even before the fix, which is why the first attempt at
    /// this looked green while the device still misbehaved.
    func testHoldingBackKeepsReversingIndefinitely() {
        let held = hold(aimDegrees: 170)
        XCTAssertEqual(held.reverseTicks, 150, "every tick must stay in reverse")
        XCTAssertFalse(held.everFlipped, "it must never hand over to the body-flip")
    }

    /// Every angle in the wedge holds, not just the one that was reported.
    func testTheWholeRearWedgeKeepsReversing() {
        for degrees in [121.0, 130, 150, 170, 180, -121, -130, -150, -170] {
            let held = hold(aimDegrees: degrees)
            XCTAssertEqual(
                held.reverseTicks, 150, accuracy: 0,
                "aiming \(degrees)° off the nose must reverse for every tick")
        }
    }

    /// **The nose must not chase the thumb while it is behind.** The tail comes
    /// around, then settles: the turn stops with the aim still in the wedge
    /// rather than rotating the nose onto the thumb.
    func testTheTailSwingsTowardTheThumbButSettles() {
        let held = hold(aimDegrees: 170)
        // The tail moved toward the thumb — a positive aim turns the car
        // positively — but nowhere near the 170° a full pirouette would reach.
        XCTAssertGreaterThan(held.endHeadingDegrees, 20, "the tail must swing toward the thumb")
        XCTAssertLessThan(
            held.endHeadingDegrees, 120,
            "but must not rotate the nose onto the thumb — that ends the reverse")
        // Settled means the aim is still outside the forward arc.
        XCTAssertGreaterThan(
            abs(170 - held.endHeadingDegrees), 120 - 1e-9,
            "the aim must remain in the rear wedge")
    }

    /// Mirrored: a leftward aim swings the tail left.
    func testTheSwingIsSymmetric() {
        let right = hold(aimDegrees: 170)
        let left = hold(aimDegrees: -170)
        XCTAssertEqual(
            left.endHeadingDegrees, -right.endHeadingDegrees, accuracy: 0.001,
            "the wedge must behave identically on both sides")
    }

    /// The forward arc is untouched: at 120° and inside, the sim's body-flip
    /// still owns the car and reverse never engages.
    func testTheForwardArcNeverReverses() {
        for degrees in [0.0, 45, 90, 119, 120, -45, -119, -120] {
            let held = hold(aimDegrees: degrees, ticks: 40)
            XCTAssertEqual(
                held.reverseTicks, 0,
                "aiming \(degrees)° off the nose is a forward chase, not a reverse")
        }
    }

    /// A car already reversing fast is never "too fast to flip" — it has
    /// nothing to flip. `reverseBelowSpeed` gates on SIGNED forward speed, so
    /// an unsigned `velocity.length` reading 91 while reversing must not close
    /// the gate.
    func testReversingPastTheFlipSpeedStillReverses() {
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        source.touchMoved(id: TouchID(1), at: Vec2(420, 500))  // straight back
        source.setCar(heading: 0, forwardSpeed: -200, speed: 200)
        let input = source.input(for: PlayerID(0), at: Tick(0))
        XCTAssertNil(input.aim, "reversing at 200 must stay in reverse")
        XCTAssertLessThan(input.throttle, 0)
    }

    /// Driving FORWARD fast at a target behind still flips — the arcade move is
    /// intact, and reverse stays a low-speed maneuver.
    func testDrivingForwardFastStillFlips() {
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        source.touchMoved(id: TouchID(1), at: Vec2(420, 500))
        source.setCar(heading: 0, forwardSpeed: 200, speed: 200)
        let input = source.input(for: PlayerID(0), at: Tick(0))
        XCTAssertNotNil(input.aim, "a fast forward car flips its body instead")
        XCTAssertGreaterThan(input.throttle, 0)
    }
}
