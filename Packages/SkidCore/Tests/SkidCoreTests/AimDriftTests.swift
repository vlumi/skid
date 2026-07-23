import XCTest

@testable import SkidCore

/// The aim channel and the body-flip drift it drives: the heading chases a
/// pointed direction at a speed-scaled rate, and the drift redirects speed
/// along the nose instead of scrubbing it (driftRetention).
final class AimDriftTests: XCTestCase {
    /// An asphalt pad big enough that a flat-out flip never leaves the
    /// ribbon: a wide straight whose half-width covers the playfield.
    private func asphaltPad() -> Track {
        Track(
            centerline: [Vec2(-10000, 0), Vec2(10000, 0)],
            width: 8000,
            startSlots: [Vec2.zero],
            size: Vec2(20000, 8000)
        )
    }

    private func race(tuning: CarTuning = CarTuning()) -> Race {
        Race(track: asphaltPad(), players: [PlayerID(0)], tuning: tuning)
    }

    private func advance(_ race: inout Race, ticks: Int, input: CarInput) {
        for _ in 0..<ticks {
            race.advance(inputs: [PlayerID(0): input])
        }
    }

    // MARK: - The flip

    func testAimFlipsBodyFarFasterThanTheWheel() {
        // Build speed along +x, then point 90° off. The body should be
        // there in a handful of ticks — long before full-lock steer could.
        var aimed = race()
        advance(&aimed, ticks: 120, input: CarInput(throttle: 1))
        advance(&aimed, ticks: 10, input: CarInput(throttle: 1, aim: .pi / 2))
        XCTAssertEqual(aimed.cars[0].state.heading, .pi / 2, accuracy: 0.05)

        // The steer path also flips now (flip-assist), but the aim commands
        // the heading directly, so it reaches the target sooner.
        var steered = race()
        advance(&steered, ticks: 120, input: CarInput(throttle: 1))
        advance(&steered, ticks: 10, input: CarInput(steer: 1, throttle: 1))
        XCTAssertLessThan(steered.cars[0].state.heading, aimed.cars[0].state.heading)
    }

    // MARK: - Steer-path flip assist

    func testSteerFlipHelpsTheWheelDrift() {
        // At speed, the same steer hold turns the body more with flip assist
        // than without — that's what lets the d-pad drift.
        func headingAfterSteer(flip: Double) -> Double {
            var r = race(tuning: CarTuning(steerFlipBoost: flip))
            advance(&r, ticks: 120, input: CarInput(throttle: 1))
            advance(&r, ticks: 12, input: CarInput(steer: 1, throttle: 1))
            return r.cars[0].state.heading
        }
        XCTAssertGreaterThan(headingAfterSteer(flip: 6), headingAfterSteer(flip: 0) * 1.2)
    }

    func testSteerFlipIsSpeedGated() {
        // Parked, the flip assist adds nothing — no inertia to flip with, so
        // the d-pad is still a plain wheel at a standstill.
        var r = race(tuning: CarTuning(steerFlipBoost: 6))
        advance(&r, ticks: 60, input: CarInput(steer: 1))
        XCTAssertEqual(r.cars[0].state.heading, 0, accuracy: 1e-9)
    }

    func testSteerFlipScalesWithAnalogAmount() {
        // A half-steer hold flips less than full — analog fine control is
        // preserved (the boost rides the actuator, not a raw on/off).
        func headingAfterSteer(_ steer: Double) -> Double {
            var r = race(tuning: CarTuning(steerFlipBoost: 6))
            advance(&r, ticks: 120, input: CarInput(throttle: 1))
            advance(&r, ticks: 12, input: CarInput(steer: steer, throttle: 1))
            return r.cars[0].state.heading
        }
        XCTAssertLessThan(headingAfterSteer(0.5), headingAfterSteer(1) * 0.85)
    }

    func testParkedCarCannotFlip() {
        // No speed, no inertia to flip with (and no spinning in place).
        var r = race()
        advance(&r, ticks: 60, input: CarInput(aim: .pi / 2))
        XCTAssertEqual(r.cars[0].state.heading, 0, accuracy: 1e-9)
    }

    func testFlipStaysGentleAtLowSpeed() {
        // The speed scaling is CURVED (squared), so at ~half speed the flip
        // is much less than half of full — slow manoeuvring stays gentle
        // rather than twitchy. Measured on the aim flip's boost term.
        func flipStep(atFractionOfTop fraction: Double) -> Double {
            var r = race(tuning: CarTuning(aimTurnRate: 0))  // isolate the boost
            // Build to roughly the target fraction of top speed.
            let target = r.tuning.maxSpeed * fraction
            while r.cars[0].state.velocity.length < target {
                advance(&r, ticks: 1, input: CarInput(throttle: 1))
            }
            let before = r.cars[0].state.heading
            advance(&r, ticks: 1, input: CarInput(throttle: 0, aim: .pi))
            return r.cars[0].state.heading - before
        }
        let half = flipStep(atFractionOfTop: 0.5)
        let full = flipStep(atFractionOfTop: 0.99)
        // Linear would give half ≈ 0.5·full; squared gives ≈ 0.25·full.
        XCTAssertLessThan(half, full * 0.35)
    }

    func testFlipAuthorityGrowsWithSpeed() {
        // The same 3-tick flip turns the body further at high speed than at
        // low speed — the handbrake-inertia scaling.
        func headingAfterFlip(buildTicks: Int) -> Double {
            var r = race()
            advance(&r, ticks: buildTicks, input: CarInput(throttle: 1))
            advance(&r, ticks: 3, input: CarInput(throttle: 1, aim: .pi))
            return r.cars[0].state.heading
        }
        let slow = headingAfterFlip(buildTicks: 25)
        let fast = headingAfterFlip(buildTicks: 600)
        XCTAssertGreaterThan(abs(fast), abs(slow) * 1.3)
    }

    // MARK: - Drift retention

    func testRetentionCarriesSpeedThroughAFlick() {
        // Flick the body 90° at speed and coast through the drift: with
        // retention the speed survives (drag aside); without it the slide
        // scrubs most of it away.
        func speedAfterDrift(retention: Double) -> Double {
            var r = race(tuning: CarTuning(driftRetention: retention))
            advance(&r, ticks: 180, input: CarInput(throttle: 1))
            advance(&r, ticks: 45, input: CarInput(aim: .pi / 2))
            return r.cars[0].state.velocity.length
        }
        let kept = speedAfterDrift(retention: 1)
        let scrubbed = speedAfterDrift(retention: 0)
        XCTAssertGreaterThan(kept, scrubbed * 1.35)
        XCTAssertGreaterThan(kept, 300)  // most of ~430 u/s survives the flick
    }

    func testRetentionNeverManufacturesSpeed() {
        // Energy-true redirect: holding a circular drift flat-out never
        // pushes the car past its top speed.
        var r = race()
        advance(&r, ticks: 600, input: CarInput(throttle: 1))
        for tick in 0..<600 {
            // Aim keeps sweeping ahead of the nose — a held circular drift.
            let heading = r.cars[0].state.heading
            let aim = heading + 0.9
            _ = tick
            advance(&r, ticks: 1, input: CarInput(throttle: 1, aim: aim))
            XCTAssertLessThanOrEqual(
                r.cars[0].state.velocity.length, r.tuning.maxSpeed + 1e-6)
        }
    }

    func testAimBehindComesBackAround() {
        // Point straight behind at speed: the body flips, the slide carries,
        // and the throttle pulls the car out travelling the way it faces.
        var r = race()
        advance(&r, ticks: 120, input: CarInput(throttle: 1))
        advance(&r, ticks: 240, input: CarInput(throttle: 1, aim: .pi))
        let car = r.cars[0].state
        XCTAssertEqual(abs(car.heading), .pi, accuracy: 0.05)
        XCTAssertLessThan(car.velocity.x, -50)  // travelling the aimed way
    }

    // MARK: - Grip (the inertia knob)

    func testLowerGripMakesTheSlideLinger() {
        // Same flick; lower gripScale = the sideways slip survives longer, so
        // the car's MOTION lags the nose (heavier, driftier "inertia").
        func slipAfterFlick(gripScale: Double) -> Double {
            var r = race(tuning: CarTuning(gripScale: gripScale))
            advance(&r, ticks: 180, input: CarInput(throttle: 1))
            advance(&r, ticks: 20, input: CarInput(aim: .pi / 2))
            return r.cars[0].state.slipSpeed
        }
        XCTAssertGreaterThan(slipAfterFlick(gripScale: 0.4), slipAfterFlick(gripScale: 1) * 1.3)
    }

    // MARK: - Determinism + recording compatibility

    func testAimInputsStayDeterministic() {
        func run() -> Race {
            var r = race()
            advance(&r, ticks: 120, input: CarInput(throttle: 1))
            advance(&r, ticks: 120, input: CarInput(throttle: 0.8, aim: 2.1))
            advance(&r, ticks: 60, input: CarInput(steer: -0.5, throttle: 1))
            return r
        }
        XCTAssertEqual(run(), run())
    }

    func testRecordingsWithoutAimStillDecode() throws {
        // A pre-aim recording: CarInput JSON with only steer/throttle.
        let old = Data(#"{"steer":0.5,"throttle":1}"#.utf8)
        let decoded = try JSONDecoder().decode(CarInput.self, from: old)
        XCTAssertNil(decoded.aim)
        XCTAssertEqual(decoded.steer, 0.5)

        // And the aim channel round-trips.
        let input = CarInput(throttle: 1, aim: .pi / 3)
        let data = try JSONEncoder().encode(input)
        XCTAssertEqual(try JSONDecoder().decode(CarInput.self, from: data), input)
    }
}
