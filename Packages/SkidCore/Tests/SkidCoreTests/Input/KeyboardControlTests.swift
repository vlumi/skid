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
}
