import XCTest

@testable import SkidCore

/// The host's state on the wire — what a client renders instead of simulating.
final class RaceSnapshotTests: XCTestCase {
    private func drivenRace(ticks: Int = 400) -> Race {
        let seats = [PlayerID(0), PlayerID(1), PlayerID(2)]
        var race = Race(track: TrackLibrary.testRing(), players: seats, seed: 7)
        for tick in 0..<ticks {
            var inputs: [PlayerID: CarInput] = [:]
            for seat in seats {
                inputs[seat] = CarInput(
                    steer: sin(Double(tick) / 30 + Double(seat.rawValue)), throttle: 1)
            }
            race.advance(inputs: inputs)
        }
        return race
    }

    func testASnapshotRoundTripsWithinDisplayPrecision() {
        // Float32 on the wire, so exact equality is wrong to ask for — but the loss
        // must stay far below a pixel at any zoom the map ever renders.
        let race = drivenRace()
        let snapshot = RaceSnapshot(of: race)
        guard let back = RaceSnapshot(bytes: snapshot.encoded) else {
            return XCTFail("the snapshot did not decode")
        }
        XCTAssertEqual(back.tick, race.tick)
        XCTAssertEqual(back.cars.count, 3)
        for (car, original) in zip(back.cars, race.cars) {
            XCTAssertEqual(car.seat, original.id)
            XCTAssertEqual(car.position.x, original.state.position.x, accuracy: 0.001)
            XCTAssertEqual(car.position.y, original.state.position.y, accuracy: 0.001)
            XCTAssertEqual(car.heading, original.state.heading, accuracy: 0.0001)
            // Progress is exact — integers survive the wire untouched.
            XCTAssertEqual(car.progress, original.progress)
        }
    }

    func testApplyingASnapshotMakesTheClientShowTheHostsRace() {
        // The client's race is a display buffer: same roster, wildly different
        // history, and one apply must bring every rendered field into line.
        let host = drivenRace()
        var client = Race(
            track: TrackLibrary.testRing(),
            players: [PlayerID(0), PlayerID(1), PlayerID(2)], seed: 7)
        guard let snapshot = RaceSnapshot(bytes: RaceSnapshot(of: host).encoded) else {
            return XCTFail("the snapshot did not decode")
        }
        client.apply(snapshot)
        XCTAssertEqual(client.tick, host.tick, "the countdown and lap timers key off this")
        for (mine, theirs) in zip(client.cars, host.cars) {
            XCTAssertEqual(mine.state.position.x, theirs.state.position.x, accuracy: 0.001)
            XCTAssertEqual(mine.state.heading, theirs.state.heading, accuracy: 0.0001)
            XCTAssertEqual(mine.progress, theirs.progress, "laps and finishes are the host's word")
        }
        // Phase falls out of tick + config, so the client agrees about that too.
        XCTAssertEqual(client.phase, host.phase)
    }

    func testASnapshotForTheWrongFieldIsRefusedWhole() {
        // Applied to a race with different seats, nothing may change — a partial
        // apply would paint some cars with another race's positions.
        let host = drivenRace()
        // Same car COUNT, different seats — the case the count guard alone cannot
        // catch. Sabotage proved the original version of this test was vacuous: it
        // used a two-car race, so removing the seat check still passed.
        var other = Race(
            track: TrackLibrary.testRing(),
            players: [PlayerID(5), PlayerID(6), PlayerID(7)], seed: 1)
        let before = other.cars
        other.apply(RaceSnapshot(of: host))
        XCTAssertEqual(other.cars, before, "a mismatched snapshot changed the race")
        XCTAssertEqual(other.tick, 0)
        // And a different count is refused too.
        var fewer = Race(track: TrackLibrary.testRing(), players: [PlayerID(0)], seed: 1)
        let fewerBefore = fewer.cars
        fewer.apply(RaceSnapshot(of: host))
        XCTAssertEqual(fewer.cars, fewerBefore)
    }

    func testInterpolationBlendsTheContinuousAndJumpsTheDiscrete() {
        let race = drivenRace(ticks: 300)
        var later = race
        for _ in 0..<30 { later.advance(inputs: [:]) }
        let a = RaceSnapshot(of: race)
        let b = RaceSnapshot(of: later)

        let mid = RaceSnapshot.interpolated(from: a, to: b, alpha: 0.5)
        for (index, car) in mid.cars.enumerated() {
            let expectedX = (a.cars[index].position.x + b.cars[index].position.x) / 2
            XCTAssertEqual(car.position.x, expectedX, accuracy: 0.001)
            // Discrete state comes from the LATER snapshot — the host said it happened.
            XCTAssertEqual(car.progress, b.cars[index].progress)
        }
        XCTAssertEqual(mid.tick, a.tick + 15)
        // Ends are exact: alpha 0 sits on the older positions, alpha 1 on the newer.
        let atStart = RaceSnapshot.interpolated(from: a, to: b, alpha: 0)
        let atEnd = RaceSnapshot.interpolated(from: a, to: b, alpha: 1)
        for index in a.cars.indices {
            XCTAssertEqual(atStart.cars[index].position, a.cars[index].position)
            XCTAssertEqual(atEnd.cars[index].position, b.cars[index].position)
        }
        XCTAssertEqual(atEnd.cars, b.cars)
    }

    func testHeadingInterpolatesTheShortWayAroundNorth() {
        // 350° to 10° is a 20° turn through north, not a 340° spin the long way.
        var a = RaceSnapshot(of: drivenRace(ticks: 10))
        var b = a
        a.cars[0].heading = 350.0 * .pi / 180
        b.cars[0].heading = 10.0 * .pi / 180
        let mid = RaceSnapshot.interpolated(from: a, to: b, alpha: 0.5)
        // Midway is due north (0°). Compare as a WRAPPED angle distance, since the
        // raw number may legally read 0 or 360.
        let offNorth = atan2(sin(mid.cars[0].heading), cos(mid.cars[0].heading))
        XCTAssertEqual(offNorth, 0, accuracy: 0.001, "took the long way around")
    }

    func testMalformedBytesAreDroppedNotBelieved() {
        let good = RaceSnapshot(of: drivenRace()).encoded
        XCTAssertNotNil(RaceSnapshot(bytes: good), "the baseline must decode")
        XCTAssertNil(RaceSnapshot(bytes: Array(good.dropLast())), "truncated")
        XCTAssertNil(RaceSnapshot(bytes: Array(good.prefix(3))), "clipped header")
        XCTAssertNil(RaceSnapshot(bytes: good + [7]), "trailing garbage")
        XCTAssertNil(RaceSnapshot(bytes: []), "empty")
        // A lying car count desynchronises every field after it.
        var lyingCount = good
        lyingCount[4] = 9
        XCTAssertNil(RaceSnapshot(bytes: lyingCount), "a wrong car count was believed")
        // Fuzz: no input may crash the decoder — it parses network data.
        var rng = SeededRNG(seed: 31)
        for length in 0..<200 {
            let junk = (0..<length).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            _ = RaceSnapshot(bytes: junk)
        }
    }

    func testTheWireStaysInsideOneDatagram() {
        // Nine cars, each with three finished laps — the fattest snapshot the
        // protocol allows — must fit a single datagram with room to spare.
        var race = Race(
            track: TrackLibrary.track(id: "eight"), players: (0..<9).map(PlayerID.init),
            seed: 1)
        for index in race.cars.indices {
            race.cars[index].progress.lapTimes = [400, 410, 395]
            race.cars[index].progress.finishedAt = 1400
        }
        XCTAssertLessThan(RaceSnapshot(of: race).encoded.count, 600)
    }
}
