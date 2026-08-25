import XCTest

@testable import SkidCore

final class PhysicsTests: XCTestCase {
    /// A long flat asphalt drag strip: straight centerline through the world
    /// middle, walls far away.
    private func dragStrip() -> Track {
        Track(
            centerline: [Vec2(-10000, 0), Vec2(10000, 0)],
            width: 400,
            startSlots: [Vec2.zero],
            size: Vec2(20000, 4000)
        )
    }

    private func race(on track: Track? = nil) -> Race {
        Race(track: track ?? dragStrip(), players: [PlayerID(0)])
    }

    private func advance(_ race: inout Race, ticks: Int, input: CarInput) {
        for _ in 0..<ticks {
            race.advance(inputs: [PlayerID(0): input])
        }
    }

    func testThrottleAcceleratesForward() {
        var r = race()
        advance(&r, ticks: 60, input: CarInput(throttle: 1))
        let car = r.cars[0].state
        XCTAssertGreaterThan(car.forwardSpeed, 100)
        XCTAssertGreaterThan(car.position.x, 0)
        XCTAssertEqual(car.position.y, 0, accuracy: 1e-9)
    }

    func testTopSpeedIsClamped() {
        var r = race()
        advance(&r, ticks: 60 * 20, input: CarInput(throttle: 1))
        XCTAssertLessThanOrEqual(r.cars[0].state.forwardSpeed, r.tuning.maxSpeed)
        // And it actually gets near the cap, drag notwithstanding.
        XCTAssertGreaterThan(r.cars[0].state.forwardSpeed, r.tuning.maxSpeed * 0.85)
    }

    func testCoastingDecays() {
        var r = race()
        advance(&r, ticks: 120, input: CarInput(throttle: 1))
        let speedBefore = r.cars[0].state.forwardSpeed
        advance(&r, ticks: 120, input: .coast)
        XCTAssertLessThan(r.cars[0].state.forwardSpeed, speedBefore)
    }

    func testBrakingStopsAndReverses() {
        var r = race()
        advance(&r, ticks: 60, input: CarInput(throttle: 1))
        advance(&r, ticks: 60 * 6, input: CarInput(throttle: -1))
        let speed = r.cars[0].state.forwardSpeed
        XCTAssertLessThan(speed, 0)
        XCTAssertGreaterThanOrEqual(speed, -r.tuning.reverseMaxSpeed - 1e-9)
    }

    func testSteeringTurnsAtSpeedButNotParked() {
        var parked = race()
        advance(&parked, ticks: 60, input: CarInput(steer: 1))
        XCTAssertEqual(parked.cars[0].state.heading, 0, accuracy: 1e-9)

        var moving = race()
        advance(&moving, ticks: 60, input: CarInput(throttle: 1))
        advance(&moving, ticks: 30, input: CarInput(steer: 1, throttle: 1))
        XCTAssertGreaterThan(moving.cars[0].state.heading, 0.1)
    }

    func testHardCorneringSlides() {
        var r = race()
        advance(&r, ticks: 90, input: CarInput(throttle: 1))
        advance(&r, ticks: 10, input: CarInput(steer: 1, throttle: 1))
        // Mid-corner the car carries lateral velocity — the drift.
        XCTAssertGreaterThan(r.cars[0].state.slipSpeed, 20)
        // And grip bleeds it off once the wheel straightens — over a longer
        // run than before speedGripFade, since at speed the bleed is now
        // deliberately slower (that is the boat feel).
        advance(&r, ticks: 150, input: CarInput(throttle: 1))
        XCTAssertLessThan(r.cars[0].state.slipSpeed, 10)
    }

    /// **Speed is what breaks the car loose.** Grip bleeds a FRACTION of the
    /// slide per tick, so without the fade the fraction retained is
    /// speed-independent — the clean property that isolates the fade itself.
    func testFastCornersKeepTheirSlideLonger() {
        // A steering pulse at a given speed, then how much of the slide
        // survives 30 straight ticks.
        func retained(runUp: Int, fade: Double) -> Double {
            var tuning = CarTuning()
            tuning.speedGripFade = fade
            var r = Race(track: dragStrip(), players: [PlayerID(0)], tuning: tuning)
            advance(&r, ticks: runUp, input: CarInput(throttle: 1))
            advance(&r, ticks: 10, input: CarInput(steer: 1, throttle: 1))
            let mid = r.cars[0].state.slipSpeed
            advance(&r, ticks: 30, input: CarInput(throttle: 1))
            return r.cars[0].state.slipSpeed / mid
        }

        // Without the fade: slow (~1 s of run-up) and flat-out (~20 s) retain
        // the SAME fraction, because a proportional bleed cannot tell them
        // apart. This is the control that proves the comparison below
        // measures the fade and not something else about speed.
        let slowFlat = retained(runUp: 30, fade: 0)
        let fastFlat = retained(runUp: 60 * 20, fade: 0)
        XCTAssertEqual(slowFlat, fastFlat, accuracy: 0.02)

        // With the fade: the flat-out car holds its slide, the slow one bites.
        let slow = retained(runUp: 30, fade: 0.5)
        let fast = retained(runUp: 60 * 20, fade: 0.5)
        XCTAssertGreaterThan(fast, slow * 1.5, "fast \(fast) vs slow \(slow)")
        // And the stock default actually HAS the effect.
        XCTAssertGreaterThan(CarTuning().speedGripFade, 0)
    }

    func testGrassIsSlowerThanAsphalt() {
        // Same drag strip, but a second run starts on grass (offset far from
        // the ribbon).
        var asphalt = race()
        advance(&asphalt, ticks: 120, input: CarInput(throttle: 1))

        let grassTrack = Track(
            centerline: [Vec2(-10000, -1500), Vec2(10000, -1500)],
            width: 400,
            startSlots: [Vec2.zero],  // 1500 from the ribbon → grass
            size: Vec2(20000, 4000)
        )
        var grass = race(on: grassTrack)
        advance(&grass, ticks: 120, input: CarInput(throttle: 1))

        XCTAssertGreaterThan(
            asphalt.cars[0].state.forwardSpeed,
            grass.cars[0].state.forwardSpeed * 1.3
        )
    }

    func testOilIsSlipperierThanAsphalt() {
        XCTAssertLessThan(Surface.oil.grip, Surface.asphalt.grip / 10)
        XCTAssertLessThan(Surface.oil.traction, Surface.asphalt.traction / 5)
        XCTAssertLessThan(Surface.grass.traction, Surface.asphalt.traction)
        XCTAssertGreaterThan(Surface.mud.drag, Surface.grass.drag)
    }

    func testWallBounceReflects() {
        var track = dragStrip()
        track.walls = [Wall(from: Vec2(300, -500), to: Vec2(300, 500))]
        var r = race(on: track)
        advance(&r, ticks: 60 * 5, input: CarInput(throttle: 0.8))
        let car = r.cars[0].state
        // The car never tunnels the wall and ends up pushed back off it.
        XCTAssertLessThan(car.position.x, 300)
    }

    func testCarInputClamps() {
        let input = CarInput(steer: 5, throttle: -7)
        XCTAssertEqual(input.steer, 1)
        XCTAssertEqual(input.throttle, -1)
    }

    func testTirePositionsRotateWithHeading() {
        let state = CarState(position: Vec2(100, 100), heading: .pi / 2)
        let tires = state.tirePositions
        XCTAssertEqual(tires.count, 4)
        // Heading +90° (math coords): rear tires sit below in y.
        XCTAssertLessThan(tires[0].y, 100)
        XCTAssertLessThan(tires[1].y, 100)
        XCTAssertGreaterThan(tires[2].y, 100)
    }

    func testPaceScalingSlowsWithoutDumbingDown() {
        let full = CarTuning()
        let learner = full.scaled(pace: 0.7)
        XCTAssertEqual(learner.maxSpeed, full.maxSpeed * 0.7, accuracy: 1e-9)
        XCTAssertEqual(learner.engineAccel, full.engineAccel * 0.7, accuracy: 1e-9)
        XCTAssertEqual(learner.brakeAccel, full.brakeAccel * 0.7, accuracy: 1e-9)
        XCTAssertEqual(learner.reverseMaxSpeed, full.reverseMaxSpeed * 0.7, accuracy: 1e-9)
        // Agility and everything else stays — slower, not clumsier.
        XCTAssertEqual(learner.turnRate, full.turnRate)
        XCTAssertEqual(learner.steerFullSpeed, full.steerFullSpeed)
        XCTAssertEqual(learner.wallRestitution, full.wallRestitution)
        XCTAssertEqual(full.scaled(pace: 1), full)
    }
}
