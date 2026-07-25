import XCTest

@testable import SkidCore

/// Elevation behaviour: climbing, descending, jumping, and — above all — that a
/// car on the road *under* a bridge stays under it.
///
/// These were written against a discrete `layer: Int` that flipped when the car
/// crossed a ramp line. That model is gone: a car now carries a continuous
/// `height` and follows the height of the road beneath it. The assertions are the
/// same behaviours, restated in height.
final class HeightTests: XCTestCase {
    /// A straight strip whose forward segment climbs to deck height in the
    /// middle, so a car driving along it goes up and comes back down. (The
    /// closing segment covers the same line on the ground, which is what makes
    /// a bridge-over-itself possible.)
    /// The climb is spread over many points, as the compiler densifies a real
    /// ramp: a two-point 0→1 step would be a cliff, and the car's per-tick height
    /// limit could never track it.
    private func rampTrack() -> Track {
        var centerline: [Vec2] = [Vec2(-10000, 0)]
        var heights: [Double] = [0]
        // Climb x=200…400, deck to x=800, descend to x=1000.
        for step in 0...20 {
            let t = Double(step) / 20
            centerline.append(Vec2(200 + 200 * t, 0))
            heights.append(t)
        }
        centerline.append(Vec2(800, 0))
        heights.append(1)
        for step in 1...20 {
            let t = Double(step) / 20
            centerline.append(Vec2(800 + 200 * t, 0))
            heights.append(1 - t)
        }
        centerline.append(Vec2(10000, 0))
        heights.append(0)
        return Track(
            centerline: centerline,
            width: 600,
            heights: heights,
            startSlots: [Vec2.zero],
            size: Vec2(20000, 4000)
        )
    }

    private func launchTrack() -> Track {
        Track(
            centerline: [Vec2(-10000, 0), Vec2(10000, 0)],
            width: 600,
            ramps: [Ramp(from: Vec2(300, -400), to: Vec2(300, 400), forward: Vec2(1, 0))],
            startSlots: [Vec2.zero],
            size: Vec2(20000, 4000)
        )
    }

    private func drive(_ race: inout Race, ticks: Int, input: CarInput = CarInput(throttle: 1)) {
        for _ in 0..<ticks {
            race.advance(inputs: [PlayerID(0): input])
        }
    }

    /// Driving over a bridge: up to deck height, then back down to the ground.
    func testTheCarClimbsAndDescendsWithTheRoad() {
        var mid = Race(track: rampTrack(), players: [PlayerID(0)])
        drive(&mid, ticks: 130)
        let position = mid.cars[0].state.position.x
        XCTAssertGreaterThan(position, 400, "should be past the climb")
        XCTAssertLessThan(position, 800, "…and not yet at the descent")
        XCTAssertGreaterThan(mid.cars[0].state.height, 0.8, "should be up on the deck")
        XCTAssertFalse(mid.cars[0].state.isAirborne)

        var race = Race(track: rampTrack(), players: [PlayerID(0)])
        drive(&race, ticks: 400)
        XCTAssertGreaterThan(race.cars[0].state.position.x, 1000)
        XCTAssertLessThan(race.cars[0].state.height, 0.2, "should be back on the ground")
    }

    /// The climb is gradual — no tick teleports the car between levels.
    func testTheClimbIsContinuous() {
        var race = Race(track: rampTrack(), players: [PlayerID(0)])
        var previous = race.cars[0].state.height
        for _ in 0..<400 {
            race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
            let height = race.cars[0].state.height
            guard !race.cars[0].state.isAirborne else {
                previous = height
                continue
            }
            XCTAssertLessThanOrEqual(
                abs(height - previous), Race.maxHeightChangePerTick + 1e-9,
                "height jumped from \(previous) to \(height) in one tick")
            previous = height
        }
    }

    func testLaunchingRampGoesBallistic() {
        var race = Race(track: launchTrack(), players: [PlayerID(0)])
        // Build speed, cross the launch line (~tick 97 at ~380 u/s).
        drive(&race, ticks: 100)
        XCTAssertGreaterThan(race.cars[0].state.position.x, 300)
        XCTAssertTrue(race.cars[0].state.isAirborne)
        let headingAtLaunch = race.cars[0].state.heading
        let speedAtLaunch = race.cars[0].state.velocity.length

        // While airborne: full steer + brake input does nothing — ballistic.
        drive(&race, ticks: 5, input: CarInput(steer: 1, throttle: -1))
        XCTAssertEqual(race.cars[0].state.heading, headingAtLaunch)
        XCTAssertEqual(race.cars[0].state.velocity.length, speedAtLaunch, accuracy: 1e-9)

        // It lands eventually and steering works again.
        drive(&race, ticks: 60, input: CarInput(steer: 1, throttle: 1))
        XCTAssertFalse(race.cars[0].state.isAirborne)
        XCTAssertNotEqual(race.cars[0].state.heading, headingAtLaunch)
    }

    /// Straying off the deck is a fall — the one place a height change is meant
    /// to be abrupt.
    func testStrayingOffTheBridgeDropsTheCar() {
        // A flat track, with the car artificially placed up in the air: there is
        // no elevated road anywhere, so it must drop.
        var track = rampTrack()
        track.heights = Array(repeating: 0, count: track.centerline.count)
        var race = Race(track: track, players: [PlayerID(0)])
        race.cars[0].state.height = 1
        drive(&race, ticks: 1)
        XCTAssertEqual(race.cars[0].state.height, 0)
        XCTAssertTrue(race.cars[0].state.isAirborne)
    }

    /// **The reported bug, and the reason layers are gone.** Driving the flat
    /// road *under* the bridge, a car used to clip a ramp's transition line
    /// off-axis and pop onto the deck without ever driving up a slope. With a
    /// continuous height there is nothing to clip: the car is at height 0, the
    /// deck is at 1, and it simply follows the road it is on.
    func testUnderBridgeRoadCannotClimbOntoDeck() throws {
        let track = TrackLibrary.track(id: "eight")
        var race = Race(track: track, players: [PlayerID(0)])
        // Find the crossing: a point where road exists at both heights.
        let crossing = try XCTUnwrap(
            track.centerline.indices.first { index in
                track.height(ofSegment: index) < 0.2
                    && track.distanceToCenterline(track.centerline[index], height: 1)
                        < track.width / 2
            })
        // Start well before the crossing, on the ground road, aimed through it.
        let count = track.centerline.count
        let start = track.centerline[(crossing + count - 6) % count]
        let target = track.centerline[crossing]
        let direction = (target - start).normalized
        race.cars[0].state.position = start
        race.cars[0].state.heading = atan2(direction.y, direction.x)
        race.cars[0].state.height = 0

        for _ in 0..<(4 * Race.tickRate) {
            race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
            XCTAssertLessThan(
                race.cars[0].state.height, 0.5,
                "a car on the under-bridge road climbed onto the deck")
        }
    }

    /// A bridge is two roads sharing one patch of ground: asphalt at both
    /// heights at the crossing, and nothing at deck height off to the side.
    func testBridgeGeometry() throws {
        let track = TrackLibrary.track(id: "eight")
        XCTAssertTrue(track.heights.contains { $0 > 0.5 }, "the Eight has a bridge")
        let crossing = try XCTUnwrap(
            track.centerline.indices.first { index in
                track.height(ofSegment: index) < 0.2
                    && track.distanceToCenterline(track.centerline[index], height: 1)
                        < track.width / 2
            })
        let point = track.centerline[crossing]
        XCTAssertEqual(track.surface(at: point, height: 0), .asphalt)
        XCTAssertEqual(track.surface(at: point, height: 1), .asphalt)
        // Far outside the track: grass at any height.
        let outside = Vec2(track.size.x - 1, track.size.y - 1)
        XCTAssertEqual(track.surface(at: outside, height: 0), .grass)
        XCTAssertEqual(track.surface(at: outside, height: 1), .grass)
    }

    /// A car on the grass stays put at ground level — it must not bounce.
    ///
    /// Reported as "the car starts jumping up and down a bit on grass sometimes",
    /// visible as dotted tyre tracks. Cause: a car on the grass beside a ramp
    /// picked up the nearby slope's height, drifted over the tolerance, was
    /// declared off-the-deck, and got a short hop — repeatedly. Only road the car
    /// is actually on may carry it.
    /// Swept over the whole infield rather than one spot, because the bug only
    /// fired near a ramp: on the old code 36 of 202 grass starts took off, and
    /// none do now.
    func testACarOnGrassDoesNotBounce() {
        let track = TrackLibrary.track(id: "eight")
        var starts = 0
        for gx in stride(from: 40.0, to: track.size.x - 40, by: 60) {
            for gy in stride(from: 40.0, to: track.size.y - 40, by: 60) {
                let start = Vec2(gx, gy)
                guard track.surface(at: start, height: 0) == .grass else { continue }
                starts += 1
                var race = Race(track: track, players: [PlayerID(0)])
                race.cars[0].state.position = start
                race.cars[0].state.height = 0
                race.cars[0].state.heading = 0.7
                race.cars[0].state.velocity = Vec2(angle: 0.7) * 300
                for _ in 0..<120 {
                    race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
                    XCTAssertFalse(
                        race.cars[0].state.isAirborne,
                        "a car driving on the grass from \(start) took off")
                }
            }
        }
        XCTAssertGreaterThan(starts, 50, "sweep must actually cover the infield")
    }

    /// **Driving on the grass under a bridge must not put you on the bridge.**
    /// Reported as "if I drive under the bridge on grass, the car appears on the
    /// bridge, and I can also drive on the ramp".
    ///
    /// The car moves before its height is resolved, so testing only the position
    /// it ARRIVED at let it cross from grass onto ramp asphalt within one tick and
    /// inherit the slope's height. Height may only come from road the car was
    /// ALREADY on, matched at its own height rather than within a whole level.
    ///
    /// Measured outcome-only, so it can't be fooled by the rule it's testing:
    /// start on the grass beneath the deck, drive, and see where you end up. 20 of
    /// 520 runs reached deck height before the fix.
    func testGrassUnderTheBridgeDoesNotLeadOntoIt() throws {
        let track = TrackLibrary.track(id: "eight")
        var starts: [Vec2] = []
        for gx in stride(from: 30.0, to: track.size.x - 30, by: 25) {
            for gy in stride(from: 30.0, to: track.size.y - 30, by: 25) {
                let point = Vec2(gx, gy)
                guard track.surface(at: point, height: 0) == .grass,
                    track.distanceToCenterline(point, height: 1) < track.width / 2
                else { continue }
                starts.append(point)
            }
        }
        XCTAssertGreaterThan(starts.count, 10, "fixture needs grass under the deck")

        var reachedDeck = 0
        for start in starts {
            for heading in stride(from: 0.0, to: 6.28, by: 0.785) {
                var race = Race(track: track, players: [PlayerID(0)])
                race.cars[0].state.position = start
                race.cars[0].state.height = 0
                race.cars[0].state.heading = heading
                race.cars[0].state.velocity = Vec2(angle: heading) * 350
                for _ in 0..<90 {
                    race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
                    if race.cars[0].state.height > 0.7 {
                        reachedDeck += 1
                        break
                    }
                }
            }
        }
        // Not zero: a car can legitimately find the ramp's mouth and drive up it,
        // which is the point of a ramp. It should be rare, not routine.
        XCTAssertLessThanOrEqual(
            reachedDeck, 3,
            "\(reachedDeck) runs from the grass under the bridge ended up on it")
    }

    /// **A car on the grass must not be drawn on the bridge.** Caught with the
    /// debug overlay: a car reading "h 0.00 / grass / off road 101" was drawn up on
    /// the deck.
    ///
    /// The renderer decides a car is climbing with `isOnRamp`, which was
    /// position-only — true for anything near sloped road, including a car on the
    /// grass beside a ramp and one on the road passing underneath it. Those were
    /// promoted into the elevated pass and drawn on the bridge. Being on a ramp
    /// now means at the ramp's height AND on its asphalt: 113 grass positions
    /// qualified before, none do now, while all 24 real ramp points still do.
    func testGrassCarsAreNotTreatedAsClimbing() {
        let track = TrackLibrary.track(id: "eight")
        func climbing(_ point: Vec2, height: Double) -> Bool {
            track.isOnRamp(point, height: height)
                && track.distanceToCenterline(point, height: height) <= track.width / 2
        }
        var grassSamples = 0
        for gx in stride(from: 20.0, to: track.size.x - 20, by: 20) {
            for gy in stride(from: 20.0, to: track.size.y - 20, by: 20) {
                let point = Vec2(gx, gy)
                guard track.surface(at: point, height: 0) == .grass else { continue }
                grassSamples += 1
                XCTAssertFalse(
                    climbing(point, height: 0),
                    "a ground car on the grass at \(point) would be drawn as climbing")
            }
        }
        XCTAssertGreaterThan(grassSamples, 100, "sweep must cover the grass")

        // …but a car actually on the slope still reads as climbing, or it would
        // draw under the bridge edge on the way up.
        let count = track.centerline.count
        var rampPoints = 0
        for index in track.centerline.indices {
            let next = (index + 1) % count
            guard abs(track.heights[next] - track.heights[index]) > 0.05 else { continue }
            rampPoints += 1
            XCTAssertTrue(
                climbing(track.centerline[index], height: track.heights[index]),
                "a car on the ramp at point \(index) should read as climbing")
        }
        XCTAssertGreaterThan(rampPoints, 0, "fixture must contain a ramp")
    }

    func testElevatedDeterminism() {
        func run() -> Race {
            var race = Race(
                track: TrackLibrary.track(id: "eight"), players: [PlayerID(0), PlayerID(1)],
                config: RaceConfig(laps: 2)
            )
            var drivers = [AIDriver.make(.hard), AIDriver.make(.medium, gridIndex: 1)]
            for _ in 0..<(30 * Race.tickRate) {
                var inputs: [PlayerID: CarInput] = [:]
                for i in drivers.indices {
                    inputs[PlayerID(i)] = drivers[i].input(
                        car: race.cars[i].state, track: race.track)
                }
                race.advance(inputs: inputs)
            }
            return race
        }
        XCTAssertEqual(run(), run())
    }
}
