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
    ) -> (
        reverseTicks: Int, everFlipped: Bool, endHeadingDegrees: Double,
        tailToThumbDegrees: Double, maxHeadingDriftDegrees: Double
    ) {
        var race = Race(
            track: flatTrack(), players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.heading = 0
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        let aim = aimDegrees * .pi / 180
        source.touchMoved(id: TouchID(1), at: Vec2(500 + cos(aim) * 80, 500 + sin(aim) * 80))

        var reverseTicks = 0
        var everFlipped = false
        var maxDrift = 0.0
        for tick in 0..<ticks {
            let car = race.cars[0].state
            source.setCar(
                heading: car.heading, forwardSpeed: car.velocity.dot(car.forward),
                speed: car.velocity.length)
            let input = source.input(for: PlayerID(0), at: Tick(tick))
            // The reverse maneuver drives the wheel directly; the forward
            // scheme hands an `aim` to the sim instead.
            if input.aim == nil { reverseTicks += 1 } else { everFlipped = true }
            maxDrift = max(maxDrift, abs(car.heading * 180 / .pi))
            race.advance(inputs: [PlayerID(0): input])
        }
        let heading = race.cars[0].state.heading
        let tailToThumb = atan2(sin(aim - heading + .pi), cos(aim - heading + .pi))
        return (
            reverseTicks, everFlipped, heading * 180 / .pi,
            tailToThumb * 180 / .pi, maxDrift)
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

    /// **The tail is driven onto the thumb** — "aim its butt at the finger".
    ///
    /// The error being nulled is the tail-to-thumb angle, so success is that
    /// angle reaching zero. An earlier attempt faded the steering out at the
    /// wedge boundary instead, which parked the car ~25° short and stopped it
    /// rotating: reported from a screenshot as backing north with the thumb NE.
    func testTheTailIsDrivenOntoTheThumb() {
        let held = hold(aimDegrees: 135, ticks: 200)
        XCTAssertEqual(
            held.tailToThumbDegrees, 0, accuracy: 1,
            "the tail must end up pointing at the thumb, not short of it")
        XCTAssertEqual(held.reverseTicks, 200, "and stay in reverse the whole way")
    }

    /// **The swing is PROMPT, not merely eventual.** A version that faded the
    /// steering out near the wedge boundary still converged given enough ticks,
    /// but crawled the last stretch — which on device read as the car simply not
    /// rotating. Measured from a standstill at a 135° thumb, 45° of tail-swing
    /// closes to 13° by tick 30 and 5° by tick 45.
    func testTheTailSwingIsPrompt() {
        XCTAssertLessThan(
            abs(hold(aimDegrees: 135, ticks: 30).tailToThumbDegrees), 20,
            "45° of swing must be most of the way done within 30 ticks")
        XCTAssertLessThan(
            abs(hold(aimDegrees: 135, ticks: 45).tailToThumbDegrees), 8,
            "and essentially complete by 45")
    }

    /// The steer must be at real strength while the aim sits just inside the
    /// wedge — the exact region the discarded settle-fade zeroed out, and the
    /// geometry of the reported screenshot (backing north, thumb 135° off).
    func testTheSteerIsStrongJustInsideTheWedge() {
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        let aim = 130.0 * .pi / 180
        source.touchMoved(
            id: TouchID(1), at: Vec2(500 + cos(aim) * 80, 500 + sin(aim) * 80))
        source.setCar(heading: 0, forwardSpeed: -100, speed: 100)
        let input = source.input(for: PlayerID(0), at: Tick(0))
        XCTAssertNil(input.aim, "130° off the nose is a reverse")
        XCTAssertGreaterThan(
            abs(input.steer), 0.6,
            "the tail-swing must bite immediately, not fade in from the boundary")
    }

    /// The screenshot, as a test: backing north with the thumb NE must swing the
    /// tail around to NE rather than continuing north.
    func testBackingNorthWithTheThumbNorthEastSwingsTheTail() {
        var race = Race(
            track: flatTrack(), players: [PlayerID(0)], config: RaceConfig(laps: nil))
        // Screen y grows down and a screen direction IS a world direction, so
        // north is -y. Backing north means the NOSE points south.
        race.cars[0].state.heading = atan2(1.0, 0.0)
        race.cars[0].state.velocity = Vec2(0, -139)
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        source.touchMoved(id: TouchID(1), at: Vec2(556, 444))  // north-east

        let aim = atan2(-1.0, 1.0)
        for tick in 0..<200 {
            let car = race.cars[0].state
            source.setCar(
                heading: car.heading, forwardSpeed: car.velocity.dot(car.forward),
                speed: car.velocity.length)
            race.advance(inputs: [PlayerID(0): source.input(for: PlayerID(0), at: Tick(tick))])
        }
        let heading = race.cars[0].state.heading
        let tailToThumb = atan2(sin(aim - heading + .pi), cos(aim - heading + .pi))
        XCTAssertEqual(
            tailToThumb * 180 / .pi, 0, accuracy: 1,
            "the tail must come around onto the north-east thumb")
    }

    /// **A thumb held straight back reverses STRAIGHT back.** The mirrored steer
    /// sign matters here: with it inverted the car drifts instead of tracking
    /// straight, reported as "it tries to turn a little".
    func testAimingStraightBackDoesNotTurn() {
        let held = hold(aimDegrees: 180, ticks: 200)
        XCTAssertEqual(
            held.maxHeadingDriftDegrees, 0, accuracy: 0.5,
            "a straight-back thumb must not induce any turn")
        XCTAssertEqual(held.reverseTicks, 200)
    }

    /// The swing converges rather than overshooting into a three-point turn —
    /// the failure mode of judging the gate afresh every tick.
    func testTheSwingDoesNotOvershootIntoAFullTurn() {
        // A 135° thumb needs 45° of swing. Anything approaching the 135° that a
        // nose-onto-thumb pirouette would take is an overshoot.
        let held = hold(aimDegrees: 135, ticks: 200)
        XCTAssertLessThan(
            held.maxHeadingDriftDegrees, 60,
            "the tail must stop at the thumb, not rotate the nose onto it")
    }

    /// **A shallow wedge angle survives entry.** At 121° with the car still
    /// rolling forwards, the first ticks of the swing move the aim back inside
    /// the forward arc; without the latch the reverse gives up after 3 ticks and
    /// hands to the body-flip, leaving the tail 180° from the thumb.
    func testAShallowWedgeAngleStaysInReverseWhileRollingForward() {
        var race = Race(
            track: flatTrack(), players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.heading = 0
        race.cars[0].state.velocity = Vec2(60, 0)  // still rolling forwards
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        let aim = 121.0 * .pi / 180
        source.touchMoved(
            id: TouchID(1), at: Vec2(500 + cos(aim) * 80, 500 + sin(aim) * 80))

        var reverseTicks = 0
        for tick in 0..<200 {
            let car = race.cars[0].state
            source.setCar(
                heading: car.heading, forwardSpeed: car.velocity.dot(car.forward),
                speed: car.velocity.length)
            let input = source.input(for: PlayerID(0), at: Tick(tick))
            if input.aim == nil { reverseTicks += 1 }
            race.advance(inputs: [PlayerID(0): input])
        }
        XCTAssertGreaterThan(
            reverseTicks, 150, "the reverse must survive its own first ticks")
        let heading = race.cars[0].state.heading
        let tailToThumb = atan2(sin(aim - heading + .pi), cos(aim - heading + .pi))
        XCTAssertEqual(
            tailToThumb * 180 / .pi, 0, accuracy: 1,
            "and still bring the tail onto the thumb")
    }

    /// The latch releases when the PLAYER aims back around the nose, so a
    /// reverse is never something the car gets stuck in.
    func testAimingForwardAgainEndsTheReverse() {
        var race = Race(
            track: flatTrack(), players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.heading = 0
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        source.touchMoved(id: TouchID(1), at: Vec2(420, 500))  // straight back

        for tick in 0..<40 {
            let car = race.cars[0].state
            source.setCar(
                heading: car.heading, forwardSpeed: car.velocity.dot(car.forward),
                speed: car.velocity.length)
            race.advance(inputs: [PlayerID(0): source.input(for: PlayerID(0), at: Tick(tick))])
        }
        XCTAssertNil(
            source.input(for: PlayerID(0), at: Tick(40)).aim, "still reversing")

        // Thumb swung to the nose.
        source.touchMoved(id: TouchID(1), at: Vec2(580, 500))
        XCTAssertNotNil(
            source.input(for: PlayerID(0), at: Tick(41)).aim,
            "aiming ahead must hand back to the forward scheme immediately")
    }

    /// Lifting the thumb clears the maneuver, so the next touch starts fresh.
    func testLiftingTheThumbClearsTheReverse() {
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        source.touchMoved(id: TouchID(1), at: Vec2(420, 500))
        source.setCar(heading: 0, forwardSpeed: -50, speed: 50)
        XCTAssertNil(source.input(for: PlayerID(0), at: Tick(0)).aim, "reversing")

        source.touchEnded(id: TouchID(1))
        // A fresh touch, on a car now driving forward fast, aimed 150° off — in
        // the wedge but far too fast to reverse. Only a leaked latch could keep
        // the reverse alive here.
        source.setCar(heading: 0, forwardSpeed: 300, speed: 300)
        source.touchBegan(id: TouchID(2), at: Vec2(500, 500))
        let aim = 150.0 * .pi / 180
        source.touchMoved(
            id: TouchID(2), at: Vec2(500 + cos(aim) * 80, 500 + sin(aim) * 80))
        XCTAssertNotNil(
            source.input(for: PlayerID(0), at: Tick(1)).aim,
            "a new touch must not inherit the previous reverse")
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
