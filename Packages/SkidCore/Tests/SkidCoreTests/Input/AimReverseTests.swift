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
///
/// The stock forward arc is 150° (a 30°-either-side rear wedge) with a 45°
/// tail-swing lock, both settled on device; the fixtures below sit inside that
/// wedge. `AimTuningTests` covers moving the arc itself.
final class AimReverseTests: XCTestCase {
    /// A flat, wide road: only the controls are under test.
    private func flatTrack() -> Track {
        Track(
            centerline: [Vec2(-9000, 0), Vec2(9000, 0)], width: 4000,
            startSlots: [Vec2(0, 0)], size: Vec2(20000, 9000))
    }

    /// What a held thumb produced.
    private struct Held {
        var reverseTicks = 0
        var everFlipped = false
        var endHeadingDegrees = 0.0
        /// Where the tail ended up relative to the thumb — zero means the tail
        /// is pointing at it, which is the whole aim of the maneuver.
        var tailToThumbDegrees = 0.0
        var maxHeadingDriftDegrees = 0.0
    }

    /// Hold a steady thumb at `aimDegrees` off the nose for `ticks`.
    private func hold(aimDegrees: Double, ticks: Int = 150) -> Held {
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
        return Held(
            reverseTicks: reverseTicks, everFlipped: everFlipped,
            endHeadingDegrees: heading * 180 / .pi,
            tailToThumbDegrees: tailToThumb * 180 / .pi,
            maxHeadingDriftDegrees: maxDrift)
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
        for degrees in [151.0, 160, 170, 175, 180, -151, -160, -170, -175] {
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
        let held = hold(aimDegrees: 165, ticks: 200)
        XCTAssertEqual(
            held.tailToThumbDegrees, 0, accuracy: 1,
            "the tail must end up pointing at the thumb, not short of it")
        XCTAssertEqual(held.reverseTicks, 200, "and stay in reverse the whole way")
    }

    /// **The swing is PROMPT, not merely eventual.** A version that faded the
    /// steering out near the wedge boundary still converged given enough ticks,
    /// but crawled the last stretch — which on device read as the car simply not
    /// rotating. Measured from a standstill at a 165° thumb, the 15° of swing
    /// closes to under 3° by tick 30 — the stock 45° lock is brisk.
    func testTheTailSwingIsPrompt() {
        XCTAssertLessThan(
            abs(hold(aimDegrees: 165, ticks: 30).tailToThumbDegrees), 20,
            "the swing must be most of the way done within 30 ticks")
        XCTAssertLessThan(
            abs(hold(aimDegrees: 165, ticks: 45).tailToThumbDegrees), 8,
            "and essentially complete by 45")
    }

    /// The steer must be at real strength while the aim sits just inside the
    /// wedge — the exact region the discarded settle-fade zeroed out, and the
    /// geometry of the reported screenshot (backing north, thumb well off the
    /// tail).
    func testTheSteerIsStrongJustInsideTheWedge() {
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        let aim = 160.0 * .pi / 180
        source.touchMoved(
            id: TouchID(1), at: Vec2(500 + cos(aim) * 80, 500 + sin(aim) * 80))
        source.setCar(heading: 0, forwardSpeed: -100, speed: 100)
        let input = source.input(for: PlayerID(0), at: Tick(0))
        XCTAssertNil(input.aim, "160° off the nose is a reverse")
        // 20° of tail error against the 45° lock: real bite. The discarded
        // settle-fade scaled this by (|error| − arc)/20°, i.e. to 0.5 here and to
        // nothing at the boundary itself.
        XCTAssertGreaterThan(
            abs(input.steer), 0.4,
            "the tail-swing must bite immediately, not fade in from the boundary")
    }

    /// The reported screenshot geometry — backing north with the thumb NE — is
    /// **135° off the tail, and so a forward chase at the stock 150° arc**, not a
    /// reverse. It reversed under the earlier 120° arc, and that is where the
    /// tail-swing bug was found; the fix is covered by the tests above at angles
    /// inside the current wedge.
    ///
    /// Kept as a boundary case because it is the one real-world geometry that was
    /// photographed: it pins WHICH scheme owns that thumb position, so a future
    /// arc change is a deliberate decision rather than a surprise.
    func testBackingNorthWithTheThumbNorthEastIsAForwardChase() {
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        source.touchMoved(id: TouchID(1), at: Vec2(556, 444))  // north-east
        // Screen y grows down and a screen direction IS a world direction, so
        // north is -y. Backing north means the NOSE points south.
        source.setCar(heading: atan2(1.0, 0.0), forwardSpeed: -139, speed: 139)

        XCTAssertNotNil(
            source.input(for: PlayerID(0), at: Tick(0)).aim,
            "135° off the tail is inside the 150° forward arc — the body-flip owns it")
    }

    /// Backing north with the thumb nearer straight back IS in the wedge, and
    /// still brings the tail around onto the thumb.
    func testBackingNorthWithACloserThumbSwingsTheTail() {
        var race = Race(
            track: flatTrack(), players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.heading = atan2(1.0, 0.0)  // nose south, backing north
        race.cars[0].state.velocity = Vec2(0, -139)
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        // 20° off straight-north: inside the 30° wedge.
        let aim = atan2(-1.0, 0.36)
        source.touchMoved(
            id: TouchID(1), at: Vec2(500 + cos(aim) * 80, 500 + sin(aim) * 80))

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
            tailToThumb * 180 / .pi, 0, accuracy: 2,
            "the tail must come around onto the thumb")
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
        // A 165° thumb needs 15° of swing. Anything approaching the 165° that a
        // nose-onto-thumb pirouette would take is an overshoot.
        let held = hold(aimDegrees: 165, ticks: 200)
        XCTAssertLessThan(
            held.maxHeadingDriftDegrees, 40,
            "the tail must stop at the thumb, not rotate the nose onto it")
    }

    /// **A shallow wedge angle survives entry.** Just inside the wedge with the
    /// car still rolling forwards, the first ticks of the swing move the aim back
    /// inside the forward arc; without the latch the reverse gives up almost at
    /// once and hands to the body-flip, leaving the tail 180° from the thumb.
    func testAShallowWedgeAngleStaysInReverseWhileRollingForward() {
        var race = Race(
            track: flatTrack(), players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.heading = 0
        race.cars[0].state.velocity = Vec2(60, 0)  // still rolling forwards
        let source = AimControlSource()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        let aim = 151.0 * .pi / 180
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
        for degrees in [0.0, 45, 90, 120, 149, 150, -45, -149, -150] {
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
