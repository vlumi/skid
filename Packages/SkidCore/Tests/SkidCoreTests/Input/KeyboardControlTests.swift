import XCTest

@testable import SkidCore

/// **The keyboard scheme**: digital Pro driving from held keys, and how one
/// keyboard splits between one or two drivers.
final class KeyboardControlTests: XCTestCase {
    private func input(_ source: KeyboardControlSource) -> CarInput {
        source.input(for: PlayerID(0), at: 0)
    }

    func testEachKeyDrivesItsAxis() {
        let cases: [(KeyboardKey, CarInput)] = [
            (.w, CarInput(throttle: 1)), (.s, CarInput(throttle: -1)),
            (.a, CarInput(steer: -1)), (.d, CarInput(steer: 1)),
            (.up, CarInput(throttle: 1)), (.down, CarInput(throttle: -1)),
            (.left, CarInput(steer: -1)), (.right, CarInput(steer: 1)),
        ]
        for (key, expected) in cases {
            let source = KeyboardControlSource()
            source.press(key)
            XCTAssertEqual(input(source), expected, "\(key)")
        }
        XCTAssertEqual(input(KeyboardControlSource()), .coast, "nothing held is not coasting")
    }

    /// Gas and a turn together is the whole game — they must combine.
    func testDiagonalsCombine() {
        let source = KeyboardControlSource()
        source.press(.w)
        source.press(.d)
        XCTAssertEqual(input(source).steer, 1)
        XCTAssertEqual(input(source).throttle, 1)
    }

    func testOppositesCancel() {
        let source = KeyboardControlSource()
        source.press(.a)
        source.press(.d)
        source.press(.w)
        source.press(.s)
        XCTAssertEqual(input(source).steer, 0)
        XCTAssertEqual(input(source).throttle, 0)
    }

    /// **Keys are held, not directions**: a lone driver on W and ↑ who lets go
    /// of W is still on the gas.
    func testReleasingOneOfTwoGasKeysKeepsTheGas() {
        let seats = KeyboardSeats()
        seats.humans = 1
        seats.press(.w)
        seats.press(.up)
        seats.release(.w)
        XCTAssertEqual(input(seats.seats[0]).throttle, 1)
        seats.release(.up)
        XCTAssertEqual(input(seats.seats[0]).throttle, 0)
    }

    /// **One driver gets both clusters; two split them**, WASD left (P1).
    func testOneDriverGetsBothClustersTwoSplitThem() {
        let seats = KeyboardSeats()
        seats.humans = 1
        for key in KeyboardKey.allCases {
            XCTAssertEqual(seats.seat(for: key), 0, "\(key) alone")
        }
        seats.humans = 2
        for key in [KeyboardKey.w, .a, .s, .d] {
            XCTAssertEqual(seats.seat(for: key), 0, "\(key) is P1's")
        }
        for key in [KeyboardKey.up, .down, .left, .right] {
            XCTAssertEqual(seats.seat(for: key), 1, "\(key) is P2's")
        }
        seats.humans = 0
        XCTAssertNil(seats.seat(for: .w), "no driver, no seat")
    }

    /// Two drivers' keys never leak into each other's car.
    func testTwoDriversAreIndependent() {
        let seats = KeyboardSeats()
        seats.humans = 2
        seats.press(.w)
        seats.press(.left)
        XCTAssertEqual(input(seats.seats[0]), CarInput(steer: 0, throttle: 1))
        XCTAssertEqual(input(seats.seats[1]), CarInput(steer: -1, throttle: 0))
    }

    /// A key pressed as P2's and released after the seat count dropped must
    /// still come up — re-routing the release would leave it stuck.
    func testAReleaseFindsTheKeyWhereverItIs() {
        let seats = KeyboardSeats()
        seats.humans = 2
        seats.press(.up)
        seats.humans = 1
        seats.release(.up)
        XCTAssertTrue(seats.seats[1].held.isEmpty, "P2's arrow stuck down")
    }

    func testReleaseAllLetsGoOfEverything() {
        let seats = KeyboardSeats()
        seats.humans = 2
        seats.press(.w)
        seats.press(.right)
        seats.releaseAll()
        XCTAssertTrue(seats.seats.allSatisfy { $0.held.isEmpty })
    }

    /// **End to end through the sim**: holding D at speed turns the car to
    /// ITS right — screen-down, from a start facing +x — so the key's sign
    /// matches what a driver expects.
    func testHoldingDTurnsTheCarRight() {
        let track = Track(
            centerline: [Vec2(-10000, 0), Vec2(10000, 0)], width: 4000,
            startSlots: [Vec2.zero], size: Vec2(20000, 8000))
        var race = Race(track: track, players: [PlayerID(0)])
        let keys = KeyboardControlSource()
        keys.press(.w)
        for _ in 0..<60 {
            race.advance(inputs: [PlayerID(0): keys.input(for: PlayerID(0), at: race.tick)])
        }
        let before = race.cars[0].state.position.y
        keys.press(.d)
        for _ in 0..<30 {
            race.advance(inputs: [PlayerID(0): keys.input(for: PlayerID(0), at: race.tick)])
        }
        XCTAssertGreaterThan(
            race.cars[0].state.position.y, before + 5, "D did not turn the car right")
    }

    // MARK: - The keyboard's turn rate

    /// **The scaled wheel produces EXACTLY the yaw of the target turn rate**,
    /// at every speed — the identity the whole design rests on, checked
    /// against the formula `Race.turn` uses.
    func testScaledWheelGivesTheTargetTurnRatesYaw() {
        let tuning = CarTuning()
        for speed in stride(from: 0.0, through: tuning.maxSpeed, by: tuning.maxSpeed / 20) {
            var car = CarState(position: .zero, heading: 0)
            car.velocity = Vec2(speed, 0)
            let wheel = KeyboardSteering.scaled(
                CarInput(steer: 1), car: car, tuning: tuning, keyTurnRate: 2
            ).steer
            let effect = min(1, speed / tuning.steerFullSpeed)
            let flip = pow(min(1, speed / tuning.maxSpeed), 2)
            let yaw = wheel * (tuning.turnRate * effect + tuning.steerFlipBoost * flip)
            let target = 2 * effect + tuning.steerFlipBoost * flip
            if speed > 0 { XCTAssertEqual(yaw, target, accuracy: 1e-9, "at \(speed)") }
            XCTAssertLessThanOrEqual(wheel, 1)
        }
    }

    /// **End to end through the sim**: on STOCK physics, a held key with
    /// `keyTurnRate` 2 turns the car as far as raw full lock does on physics
    /// tuned to `turnRate` 2 — within the sliver the wheel's slew rate adds.
    func testAKeyTurnRateDrivesLikeThatPhysicsTurnRate() {
        func heading(stockKeys: Bool) -> Double {
            var tuning = CarTuning()
            if !stockKeys { tuning.turnRate = 2 }
            let track = Track(
                centerline: [Vec2(-10000, 0), Vec2(10000, 0)], width: 4000,
                startSlots: [Vec2.zero], size: Vec2(20000, 8000))
            var race = Race(track: track, players: [PlayerID(0)], tuning: tuning)
            for tick in 0..<120 {
                var input = CarInput(steer: tick < 60 ? 0 : 1, throttle: 1)
                if stockKeys {
                    input = KeyboardSteering.scaled(
                        input, car: race.cars[0].state, tuning: race.tuning, keyTurnRate: 2)
                }
                race.advance(inputs: [PlayerID(0): input])
            }
            return race.cars[0].state.heading
        }
        let keys = heading(stockKeys: true)
        let physics = heading(stockKeys: false)
        XCTAssertGreaterThan(physics, 0.2, "fixture: the car barely turned")
        XCTAssertEqual(keys, physics, accuracy: physics * 0.05)
    }

    /// Straight ahead stays straight, and a key turn rate at or above stock
    /// asks for no more than full lock.
    func testScalingLeavesStraightAloneAndNeverExceedsFullLock() {
        var car = CarState(position: .zero, heading: 0)
        car.velocity = Vec2(300, 0)
        XCTAssertEqual(
            KeyboardSteering.scaled(
                CarInput(throttle: 1), car: car, tuning: CarTuning(), keyTurnRate: 2),
            CarInput(throttle: 1))
        XCTAssertEqual(
            KeyboardSteering.scaled(
                CarInput(steer: -1), car: car, tuning: CarTuning(), keyTurnRate: 9
            ).steer, -1)
    }
}
