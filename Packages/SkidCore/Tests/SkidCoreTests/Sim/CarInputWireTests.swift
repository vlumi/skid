import XCTest

@testable import SkidCore

/// Four bytes per player per tick, and — the part that matters more — the same
/// four bytes on both peers, so two devices step from identical numbers rather
/// than two float paths hoping to agree.
final class CarInputWireTests: XCTestCase {
    private func roundTrip(_ input: CarInput) -> CarInput { CarInputWire(input).input }

    // MARK: - Size

    func testAnInputIsFourBytes() {
        // The claim in the plan, pinned. 24 bytes of Doubles → 4.
        XCTAssertEqual(CarInputWire.byteCount, 4)
        XCTAssertEqual(MemoryLayout<CarInputWire>.size, CarInputWire.byteCount)
        // And the thing it replaces really is 24, so the 6× is not folklore.
        XCTAssertEqual(MemoryLayout<Double>.size * 3, 24)
    }

    // MARK: - The values that must survive exactly

    func testCentreAndFullLockAreExact() {
        // A stick at rest must quantise to rest. If centre drifted, every car
        // would pull to one side for the whole race — the single worst failure
        // this encoding could have.
        XCTAssertEqual(roundTrip(CarInput(steer: 0, throttle: 0)).steer, 0)
        XCTAssertEqual(roundTrip(CarInput(steer: 0, throttle: 0)).throttle, 0)
        // And the ends, so full lock is full lock rather than 0.992.
        for value in [-1.0, 1.0] {
            XCTAssertEqual(roundTrip(CarInput(steer: value)).steer, value)
            XCTAssertEqual(roundTrip(CarInput(throttle: value)).throttle, value)
        }
    }

    func testTheAxesAreSymmetric() {
        // Left and right must quantise the same way. Using the full −128…127
        // range of Int8 would make them differ by a step, so a car held at full
        // left would turn slightly harder than one held at full right.
        for magnitude in stride(from: 0.0, through: 1.0, by: 0.05) {
            let positive = roundTrip(CarInput(steer: magnitude)).steer
            let negative = roundTrip(CarInput(steer: -magnitude)).steer
            XCTAssertEqual(positive, -negative, accuracy: 1e-15, "asymmetric at \(magnitude)")
        }
    }

    func testTheAxesResolveFinerThanAThumb() {
        // 127 steps per side is under 0.008 of full lock. A thumb on glass does
        // not resolve that, which is the whole argument for one byte.
        var worst = 0.0
        for value in stride(from: -1.0, through: 1.0, by: 0.001) {
            worst = max(worst, abs(roundTrip(CarInput(steer: value)).steer - value))
        }
        XCTAssertLessThan(worst, 1.0 / 127 / 2 + 1e-12, "steer step is coarser than claimed")
        XCTAssertLessThan(worst, 0.005)
    }

    func testOutOfRangeInputIsClamped() {
        // `steer` and `throttle` are `public var`, so `CarInput.init`'s clamp is
        // bypassable by assignment — and the encoder must not trust it. Going
        // through the initialiser instead makes this test vacuous: it then proves
        // `CarInput` clamps, which is a different file's job.
        var wild = CarInput()
        wild.steer = 99
        wild.throttle = -99
        XCTAssertEqual(wild.steer, 99, "assignment no longer bypasses the clamp; rewrite this test")
        // Without the encoder's own clamp this traps or wraps to the far lock —
        // a full-right command arriving as full left.
        XCTAssertEqual(roundTrip(wild).steer, 1)
        XCTAssertEqual(roundTrip(wild).throttle, -1)
        // NaN and infinity have no Int8 to round to, and would TRAP — a
        // malformed packet from a peer crashing the app rather than driving
        // badly. `max(-1, min(1, nan))` is `nan` in Swift, so the ordinary clamp
        // does not catch it.
        for bad in [Double.nan, .infinity, -.infinity, .signalingNaN] {
            var broken = CarInput()
            broken.steer = bad
            broken.throttle = bad
            XCTAssertEqual(roundTrip(broken).steer, 0, "steer \(bad) must land somewhere safe")
            XCTAssertEqual(roundTrip(broken).throttle, 0, "throttle \(bad) must land safely")
            // An unusable aim is no aim: hand the car to the steer channel rather
            // than pointing it at NaN.
            XCTAssertNil(roundTrip(CarInput(aim: bad)).aim, "aim \(bad) must not be honoured")
        }
    }

    // MARK: - Aim

    func testAimSurvivesFinelyEnoughToSteerBy() {
        // 65 535 steps over a full turn: ~0.0055°, three orders finer than a
        // thumb. Compared as a WRAPPED difference because that is how the sim
        // consumes aim (`atan2(sin(d), cos(d))`) — 0 and 2π are one direction.
        var worst = 0.0
        for degrees in stride(from: -180.0, through: 180.0, by: 0.5) {
            let radians = degrees * .pi / 180
            guard let back = roundTrip(CarInput(aim: radians)).aim else {
                return XCTFail("aim went nil at \(degrees)°")
            }
            let difference = back - radians
            worst = max(worst, abs(atan2(sin(difference), cos(difference))))
        }
        XCTAssertLessThan(worst, 0.0002, "aim lost precision")
        // And it really is fine-grained, not just within a loose bound.
        XCTAssertLessThan(worst, 2 * Double.pi / 65_535, "coarser than one full-turn step")
    }

    func testAimIsADirectionNotANumber() {
        // The sim wraps, so equivalent directions must be equivalent commands.
        // Asserting raw equality here would be asserting a coordinate convention
        // the sim does not have.
        let east = roundTrip(CarInput(aim: 0)).aim
        let alsoEast = roundTrip(CarInput(aim: 2 * .pi)).aim
        XCTAssertEqual(east, alsoEast)
        // π and −π are the same heading and must not straddle the encoding's seam.
        let plus = roundTrip(CarInput(aim: .pi)).aim
        let minus = roundTrip(CarInput(aim: -.pi)).aim
        XCTAssertEqual(try XCTUnwrap(plus), try XCTUnwrap(minus), accuracy: 1e-9)
    }

    func testNoAimIsDistinctFromAimOfZero() {
        // `nil` means "steer channel"; 0 means "point east". Collapsing them
        // would silently switch every steer-scheme car to aim mode — the reason
        // the encoding reserves a bit pattern rather than sending a flag byte.
        XCTAssertNil(roundTrip(CarInput(steer: 0.5, aim: nil)).aim)
        XCTAssertEqual(roundTrip(CarInput(steer: 0.5, aim: 0)).aim, 0)
    }

    func testTheReservedPatternIsNotReachableByARealAim() {
        // A hair under a full turn must not round up into the "no aim" pattern.
        // If it did, a car pointed a thousandth of a degree short of east would
        // abruptly fall back to the steer channel.
        for radians in [2 * Double.pi - 1e-12, 2 * Double.pi - 1e-9, -1e-12, -1e-9] {
            XCTAssertNotNil(roundTrip(CarInput(aim: radians)).aim, "aim \(radians) became nil")
        }
    }

    // MARK: - Determinism, which is the actual point

    func testQuantisingIsIdempotent() {
        // Round-tripping a value that came off the wire must not move it again.
        // If it did, a peer that quantised twice (send, receive, forward) would
        // drift from one that quantised once.
        for value in stride(from: -1.0, through: 1.0, by: 0.013) {
            let once = roundTrip(CarInput(steer: value, throttle: -value, aim: value * 3))
            XCTAssertEqual(roundTrip(once), once, "not idempotent at \(value)")
        }
    }

    func testAQuantisedRaceIsStillDeterministic() {
        // The real requirement: stepping the sim from quantised inputs must be
        // as reproducible as stepping it from raw ones, tick by tick.
        let a = quantisedHashes(seed: 11, ticks: 600)
        let b = quantisedHashes(seed: 11, ticks: 600)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 600)
        XCTAssertEqual(Set(a).count, a.count, "hash repeated while cars moved")
    }

    func testQuantisingChangesTheRaceAndSoMustBeAppliedEverywhere() {
        // Quantising is lossy, so a quantised race differs from a raw one — which
        // is exactly why it cannot be applied on only one side. A peer sending
        // quantised input while stepping its own raw thumb value diverges, and
        // this test is what says so out loud.
        let raw = rawHashes(seed: 11, ticks: 600)
        let quantised = quantisedHashes(seed: 11, ticks: 600)
        XCTAssertNotEqual(raw, quantised, "quantising is lossless? then a peer could skip it")
        // Same grid, so they start together and part company as inputs bite.
        XCTAssertEqual(raw.first, quantised.first)
    }

    // MARK: - Encoding

    func testWireEncodesAsCodable() {
        // Recordings and ghosts are input streams; the wire form has to persist.
        let inputs = [
            CarInput(steer: 0.5, throttle: -0.25, aim: 1.5), CarInput(), CarInput(aim: -3),
        ].map(CarInputWire.init)
        let data = try? JSONEncoder().encode(inputs)
        let back = try? JSONDecoder().decode([CarInputWire].self, from: XCTUnwrap(data))
        XCTAssertEqual(back, inputs)
    }

    // MARK: - Support

    private func scriptedInput(player: PlayerID, tick: Tick) -> CarInput {
        // Drives the AIM channel, unlike the steer-based determinism scripts —
        // otherwise the two-byte half of this encoding goes untested in a race.
        let phase = Double(tick) / 60.0
        return CarInput(
            throttle: tick % 240 < 200 ? 1 : -1,
            aim: sin(phase * 0.9 + Double(player.rawValue)) * .pi)
    }

    private func hashes(seed: UInt64, ticks: Int, quantise: Bool) -> [UInt64] {
        let ids = (0..<4).map { PlayerID($0) }
        var race = Race(track: TrackLibrary.testRing(), players: ids, seed: seed)
        var hashes: [UInt64] = []
        for _ in 0..<ticks {
            var inputs: [PlayerID: CarInput] = [:]
            for id in ids {
                let input = scriptedInput(player: id, tick: race.tick)
                inputs[id] = quantise ? input.quantised : input
            }
            race.advance(inputs: inputs)
            hashes.append(race.stateHash)
        }
        return hashes
    }

    private func rawHashes(seed: UInt64, ticks: Int) -> [UInt64] {
        hashes(seed: seed, ticks: ticks, quantise: false)
    }

    private func quantisedHashes(seed: UInt64, ticks: Int) -> [UInt64] {
        hashes(seed: seed, ticks: ticks, quantise: true)
    }
}
