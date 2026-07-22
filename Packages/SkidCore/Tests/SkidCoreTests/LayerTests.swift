import XCTest

@testable import SkidCore

final class LayerTests: XCTestCase {
    /// A straight strip with a ramp up at x=300 and down at x=900. The
    /// forward segment doubles as the elevated ribbon (the closing segment
    /// covers the same line on the ground), so both layers have road here.
    private func rampTrack(launches: Bool = false) -> Track {
        Track(
            centerline: [Vec2(-10000, 0), Vec2(10000, 0)],
            width: 600,
            elevatedSegments: [0],
            ramps: [
                Ramp(
                    from: Vec2(300, -400), to: Vec2(300, 400), forward: Vec2(1, 0),
                    launches: launches),
                Ramp(
                    from: Vec2(900, -400), to: Vec2(900, 400), forward: Vec2(1, 0),
                    fromLayer: 1, toLayer: 0),
            ],
            startSlots: [Vec2.zero],
            size: Vec2(20000, 4000)
        )
    }

    private func drive(_ race: inout Race, ticks: Int, input: CarInput = CarInput(throttle: 1)) {
        for _ in 0..<ticks {
            race.advance(inputs: [PlayerID(0): input])
        }
    }

    func testRampsSwitchLayersBothWays() {
        // Up at x=300 (crossed ~tick 97), down at x=900.
        var race = Race(track: rampTrack(), players: [PlayerID(0)])
        drive(&race, ticks: 240)
        XCTAssertGreaterThan(race.cars[0].state.position.x, 900)
        XCTAssertEqual(race.cars[0].state.layer, 0)

        // Between the ramps: the intermediate layer.
        var mid = Race(track: rampTrack(), players: [PlayerID(0)])
        drive(&mid, ticks: 115)
        XCTAssertGreaterThan(mid.cars[0].state.position.x, 300)
        XCTAssertLessThan(mid.cars[0].state.position.x, 900)
        XCTAssertEqual(mid.cars[0].state.layer, 1)
        XCTAssertFalse(mid.cars[0].state.isAirborne)
    }

    func testLaunchingRampGoesBallistic() {
        var race = Race(track: rampTrack(launches: true), players: [PlayerID(0)])
        // Build speed, cross the launch ramp (~tick 97 at ~380 u/s).
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

    func testStrayingOffTheBridgeDropsTheCar() {
        // Elevated ribbon exists only far away; an elevated car in the
        // middle of nowhere must fall back to ground with a short drop.
        var track = rampTrack()
        track.elevatedSegments = []  // no elevated ribbon at all
        var race = Race(track: track, players: [PlayerID(0)])
        race.cars[0].state.layer = 1
        drive(&race, ticks: 1)
        XCTAssertEqual(race.cars[0].state.layer, 0)
        XCTAssertTrue(race.cars[0].state.isAirborne)
    }

    func testRampCannotBeEnteredSideways() {
        // Drive straight at the side of the Overpass approach ramp: the
        // retaining wall bounces the car; it never reaches the ramp lane.
        var race = Race(track: TrackLibrary.overpass(), players: [PlayerID(0)])
        let approachMid = (Vec2(950, 190) + Vec2(905, 293)) * 0.5
        let side = (Vec2(905, 293) - Vec2(950, 190)).normalized.perpendicular
        race.cars[0].state.position = approachMid + side * 220
        race.cars[0].state.heading = atan2(-side.y, -side.x)  // aimed at the ramp
        for _ in 0..<(3 * Race.tickRate) {
            race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
        }
        let toRamp = race.cars[0].state.position.distance(to: approachMid)
        XCTAssertGreaterThan(toRamp, 40, "car pushed through the ramp's retaining wall")
        XCTAssertEqual(race.cars[0].state.layer, 0)
    }

    func testReversingBackOverTheBridgeStaysOnDeck() {
        // Device repro: reversing from the descent ramp back over the
        // bridge left the car on layer 0 under the deck (a bubble the
        // whole way). Reverse the full span and assert the car rides ON
        // the deck.
        var race = Race(track: TrackLibrary.overpass(), players: [PlayerID(0)])
        let diveStart = Vec2(950, 190)
        let diveEnd = Vec2(700, 760)
        let dir = (diveEnd - diveStart).normalized
        race.cars[0].state.position = diveStart + (diveEnd - diveStart) * 0.95
        race.cars[0].state.heading = atan2(dir.y, dir.x)  // facing down-slope
        var sawDeck = false
        for _ in 0..<(10 * Race.tickRate) {
            race.advance(inputs: [PlayerID(0): CarInput(throttle: -1)])
            let t =
                (race.cars[0].state.position - diveStart).dot(dir)
                / diveStart.distance(to: diveEnd)
            if t > 0.35, t < 0.65 {
                sawDeck = true
                XCTAssertEqual(
                    race.cars[0].state.layer, 1,
                    "reversing onto the bridge must climb to the deck")
                XCTAssertFalse(race.cars[0].state.isAirborne)
            }
        }
        XCTAssertTrue(sawDeck, "car never traversed the deck in reverse")
    }

    func testOverpassBridgeGeometry() {
        let track = TrackLibrary.overpass()
        XCTAssertFalse(track.elevatedSegments.isEmpty)
        XCTAssertEqual(track.ramps.count, 2)
        // The 2D crossing point of the two diagonals: asphalt on BOTH
        // layers — two roads sharing the same spot of the world.
        let crossing = Vec2(785, 566)
        XCTAssertEqual(track.surface(at: crossing, layer: 1), .asphalt)
        XCTAssertEqual(track.surface(at: crossing, layer: 0), .asphalt)
        // Off to the side of the bridge on layer 1: nothing there.
        XCTAssertEqual(track.surface(at: Vec2(1100, 620), layer: 1), .grass)
        // The bridge gate is elevated; gates elsewhere are grounded.
        XCTAssertEqual(track.gates[1].layer, 1)
        XCTAssertEqual(track.gates[3].layer, 0)
    }

    func testLayeredDeterminism() {
        func run() -> Race {
            var race = Race(
                track: TrackLibrary.overpass(), players: [PlayerID(0), PlayerID(1)],
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
