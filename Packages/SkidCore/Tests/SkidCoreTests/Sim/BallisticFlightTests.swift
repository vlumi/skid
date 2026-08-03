import XCTest

@testable import SkidCore

/// **Everything that leaves the road follows one curve.** A fall off a deck, a
/// launch off a jump lip, and (later) a slide off a banked curve are the same
/// event: the car left the road at some height and gravity brings it down.
///
/// Before this, flight was a horizontal glide — `airborneTicks` counted down
/// while `height` was never touched, and a deck fall *snapped* height to 0 and
/// then flew for 8 ticks, so the car was already at the bottom before it
/// visually landed.
final class BallisticFlightTests: XCTestCase {
    private func deckTrack() -> Track {
        // swiftlint:disable:next force_try
        try! PieceCompiler.compile(TrackCode.decode(TestTracks.Code.bridgeRing), id: "t")
    }

    /// A car pushed off the side of a deck falls, rather than teleporting down.
    func testFallingOffADeckDescendsOverTime() {
        let track = deckTrack()
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.height = 1
        race.cars[0].state.position = Vec2(-200, 600)  // off the road entirely
        race.cars[0].state.velocity = .zero

        var heights: [Double] = []
        for _ in 0..<30 {
            race.advance(inputs: [PlayerID(0): .coast])
            heights.append(race.cars[0].state.height)
        }

        XCTAssertLessThan(heights[0], 1, "it should be falling by the first tick")
        XCTAssertGreaterThan(heights[0], 0.9, "but nowhere near the bottom yet")
        XCTAssertEqual(heights.last!, 0, accuracy: 0.001, "and land at the ground")
        // Strictly monotonic on the way down — no snap, no bounce.
        for (a, b) in zip(heights, heights.dropFirst()) where b > 0 {
            XCTAssertLessThan(b, a + 0.0001, "height must only ever decrease while falling")
        }
    }

    /// Gravity accelerates: the second half of a drop covers more than the first.
    func testTheFallAccelerates() {
        let track = deckTrack()
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.height = 1
        race.cars[0].state.position = Vec2(-200, 600)

        var heights: [Double] = []
        for _ in 0..<10 {
            race.advance(inputs: [PlayerID(0): .coast])
            heights.append(race.cars[0].state.height)
        }
        let firstDrop = 1 - heights[0]
        let laterDrop = heights[heights.count - 2] - heights[heights.count - 1]
        XCTAssertGreaterThan(laterDrop, firstDrop * 1.5, "a fall must speed up")
    }

    /// Landing stops the fall — the car does not sink through the ground.
    func testLandingStopsTheFall() {
        let track = deckTrack()
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.height = 1
        race.cars[0].state.position = Vec2(-200, 600)

        for _ in 0..<120 { race.advance(inputs: [PlayerID(0): .coast]) }
        XCTAssertEqual(race.cars[0].state.height, 0, accuracy: 0.001)
        XCTAssertFalse(race.cars[0].state.isAirborne, "flight ends on landing")
    }

    /// **Flight ends by meeting a surface, not by a timer.** A higher car is in
    /// the air longer, which a fixed tick count could never express.
    func testAHigherFallTakesLonger() {
        func ticksToLand(from height: Double) -> Int {
            let track = deckTrack()
            var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
            race.cars[0].state.height = height
            race.cars[0].state.position = Vec2(-200, 600)
            for tick in 0..<300 {
                race.advance(inputs: [PlayerID(0): .coast])
                if !race.cars[0].state.isAirborne { return tick }
            }
            return 300
        }
        XCTAssertGreaterThan(ticksToLand(from: 1.0), ticksToLand(from: 0.3))
    }

    /// **A fall lands on what is BENEATH it, not always the ground.** This is
    /// what lets a jump go from the ground onto a deck, and a fall from an upper
    /// storey settle on a lower one rather than dropping through.
    func testAFallLandsOnTheRoadBeneathIt() {
        // A flat road held at height 1: a car dropped above it must stop there,
        // not continue to 0.
        var track = deckTrack()
        track.heights = Array(repeating: 1, count: track.centerline.count)
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.position = track.centerline[0]
        race.cars[0].state.height = 1.6
        race.cars[0].state.airborneTicks = 1

        for _ in 0..<120 { race.advance(inputs: [PlayerID(0): .coast]) }
        XCTAssertEqual(
            race.cars[0].state.height, 1, accuracy: 0.01,
            "it must come to rest on the road at 1, not fall through to 0")
    }

    /// **The launch kick scales with speed**, so jump distance stays quadratic —
    /// the "be fast or fall in" gate. With a fixed kick, flight time would be
    /// the same at any speed and distance would grow only linearly.
    func testAFasterLaunchFliesFurther() {
        func flight(atSpeed speed: Double) -> (ticks: Int, distance: Double) {
            let track = Track(
                centerline: [Vec2(-10000, 0), Vec2(10000, 0)], width: 600,
                ramps: [Ramp(from: Vec2(300, -400), to: Vec2(300, 400), forward: Vec2(1, 0))],
                startSlots: [Vec2(0, 0)], size: Vec2(20000, 4000))
            var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
            race.cars[0].state.position = Vec2(280, 0)
            race.cars[0].state.velocity = Vec2(speed, 0)
            var launchX = 0.0, ticks = 0
            for _ in 0..<300 {
                race.advance(inputs: [PlayerID(0): .coast])
                let car = race.cars[0].state
                if car.isAirborne {
                    if ticks == 0 { launchX = car.position.x }
                    ticks += 1
                } else if ticks > 0 {
                    return (ticks, car.position.x - launchX)
                }
            }
            return (ticks, 0)
        }

        let slow = flight(atSpeed: 260)
        let fast = flight(atSpeed: 520)
        XCTAssertGreaterThan(slow.ticks, 0, "the slow car must still launch")
        XCTAssertGreaterThan(
            fast.ticks, slow.ticks + 2,
            "twice the speed must buy meaningfully more AIR TIME, not just more ground covered")
        XCTAssertGreaterThan(
            fast.distance, slow.distance * 3,
            "quadratic: doubling speed should roughly quadruple the gap cleared")
    }

    /// A car on the road is not airborne, and its height is unaffected.
    func testDrivingOnTheRoadIsNotFlight() {
        let track = deckTrack()
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
        for _ in 0..<30 { race.advance(inputs: [PlayerID(0): .init(steer: 0, throttle: 1)]) }
        XCTAssertFalse(race.cars[0].state.isAirborne)
        XCTAssertEqual(race.cars[0].state.height, 0, accuracy: 0.001)
    }

    /// Flight is ballistic: no steering, no throttle, no drag. Horizontal
    /// velocity is carried unchanged until landing.
    func testHorizontalVelocityIsUnchangedInFlight() {
        let track = deckTrack()
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.height = 1
        race.cars[0].state.position = Vec2(-200, 600)
        race.cars[0].state.velocity = Vec2(0, -140)

        // One tick to enter flight: `applyRamps` runs after `step`, so the tick
        // that NOTICES the car left the road has already moved it as grounded.
        race.advance(inputs: [PlayerID(0): .coast])
        XCTAssertTrue(race.cars[0].state.isAirborne)
        let entry = race.cars[0].state.velocity

        race.advance(inputs: [PlayerID(0): .init(steer: 1, throttle: 1)])
        let mid = race.cars[0].state.velocity
        XCTAssertEqual(mid.x, entry.x, accuracy: 0.001, "steering must not bite in the air")
        XCTAssertEqual(mid.y, entry.y, accuracy: 0.001, "nor throttle or drag")
    }
}
