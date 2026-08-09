import XCTest

@testable import SkidCore
@testable import SkidKit

/// Global seat numbering, which the plan called out as "the first bug this design
/// would hit": two phones each thinking they own seats 0–1 means every car is
/// driven by two thumbs.
final class RaceRosterTests: XCTestCase {
    func testSeatNumbersAreGlobalNotPerDevice() {
        // The whole point. Two devices bringing two players each must get 0,1 and
        // 2,3 — never 0,1 and 0,1.
        var roster = RaceRoster()
        let first = try? roster.join("phone-a", seats: 2)
        let second = try? roster.join("phone-b", seats: 2)
        XCTAssertEqual(first, [PlayerID(0), PlayerID(1)])
        XCTAssertEqual(second, [PlayerID(2), PlayerID(3)])
        XCTAssertEqual(Set(first ?? []).intersection(Set(second ?? [])), [], "seats collided")
        XCTAssertEqual(roster.seatCount, 4)
        XCTAssertEqual(roster.seats, (0..<4).map(PlayerID.init))
    }

    func testEachDeviceKnowsOnlyItsOwnSeats() {
        // A device drives its own thumbs and simulates everybody's car, so it has
        // to be able to tell the two sets apart.
        var roster = RaceRoster()
        try? roster.join("a", seats: 1)
        try? roster.join("b", seats: 3)
        XCTAssertEqual(roster.seats(for: "a"), [PlayerID(0)])
        XCTAssertEqual(roster.seats(for: "b"), [PlayerID(1), PlayerID(2), PlayerID(3)])
        XCTAssertEqual(roster.seats(for: "nobody"), [])
    }

    func testASeatMapsBackToTheDeviceDrivingIt() {
        // For "waiting for Ville's phone" chrome: a stall names a seat, and the
        // player needs to know whose device that is.
        var roster = RaceRoster()
        try? roster.join("a", seats: 2)
        try? roster.join("b", seats: 2)
        XCTAssertEqual(roster.peer(driving: PlayerID(0)), "a")
        XCTAssertEqual(roster.peer(driving: PlayerID(3)), "b")
        XCTAssertNil(roster.peer(driving: PlayerID(8)))
    }

    func testTheHostIsWhoeverJoinedFirst() {
        var roster = RaceRoster()
        XCTAssertNil(roster.host, "an empty roster has no host")
        try? roster.join("host-phone", seats: 1)
        try? roster.join("guest", seats: 1)
        XCTAssertEqual(roster.host, "host-phone")
        XCTAssertEqual(roster.peers, ["host-phone", "guest"])
    }

    // MARK: - Refusing a join

    func testTheSameDeviceCannotJoinTwice() {
        // A duplicate join would double that device's cars — and a re-invitation
        // after a flaky connection is exactly how it would happen.
        var roster = RaceRoster()
        try? roster.join("a", seats: 2)
        XCTAssertThrowsError(try roster.join("a", seats: 1)) { error in
            XCTAssertEqual(error as? RaceRoster.JoinError, .alreadyJoined("a"))
        }
        XCTAssertEqual(roster.seatCount, 2, "a rejected join still changed the roster")
    }

    func testTheFieldFillsToItsCapAndThenRefuses() {
        var roster = RaceRoster()
        for index in 0..<(RaceRoster.maxSeats / RaceRoster.maxSeatsPerDevice) {
            try? roster.join("device-\(index)", seats: RaceRoster.maxSeatsPerDevice)
        }
        let remaining = RaceRoster.maxSeats - roster.seatCount
        XCTAssertEqual(remaining, RaceRoster.maxSeats % RaceRoster.maxSeatsPerDevice)

        // One more than fits must be refused with what WOULD have fit, so a lobby
        // can say "room for 1" rather than just "no".
        XCTAssertThrowsError(try roster.join("late", seats: remaining + 1)) { error in
            XCTAssertEqual(
                error as? RaceRoster.JoinError,
                .fieldFull(requested: remaining + 1, available: remaining))
        }
        // And exactly what fits is accepted.
        XCTAssertNoThrow(try roster.join("late", seats: remaining))
        XCTAssertEqual(roster.seatCount, RaceRoster.maxSeats)
    }

    func testADeviceCannotClaimMoreSeatsThanARigLaysOut() {
        // The seat count arrives from another device, so it is untrusted input: a
        // peer claiming 99 seats would otherwise fill the field by itself.
        var roster = RaceRoster()
        XCTAssertThrowsError(try roster.join("greedy", seats: 99)) { error in
            XCTAssertEqual(
                error as? RaceRoster.JoinError,
                .seatCountOutOfRange(requested: 99, max: RaceRoster.maxSeatsPerDevice))
        }
        // Zero seats is not a spectator mode — it is a malformed claim.
        XCTAssertThrowsError(try roster.join("empty", seats: 0))
        XCTAssertThrowsError(try roster.join("negative", seats: -1))
        XCTAssertEqual(roster.seatCount, 0)
    }

    func testTheProtocolCapIsNotTheLocalSoftCap() {
        // `CouchGame.maxCars` is 4 today for device-performance reasons, and the
        // protocol's ceiling is 9. Conflating them would bake a temporary
        // performance decision into the wire format.
        XCTAssertEqual(RaceRoster.maxSeats, 9)
        XCTAssertEqual(RaceRoster.maxSeats, PieceCompiler.Grid.slots, "grid and protocol disagree")
        XCTAssertGreaterThan(RaceRoster.maxSeats, CouchGame.maxCars)
    }

    func testTheLocalAndProtocolPerDeviceCapsCannotDrift() {
        // Two independent 4s would drift, and a peer whose UI offered a seat the
        // protocol refused would fail to join for no visible reason.
        XCTAssertEqual(CouchGame.maxLocalPlayers, RaceRoster.maxSeatsPerDevice)
    }

    // MARK: - Leaving

    func testARemovedDeviceDoesNotRenumberTheOthers() {
        // Compacting seats would change somebody else's colour and grid slot — and
        // mid-race it would be a different race on every peer. So holes are legal.
        var roster = RaceRoster()
        try? roster.join("a", seats: 2)
        try? roster.join("b", seats: 2)
        try? roster.join("c", seats: 1)
        roster.remove(peer: "b")
        XCTAssertEqual(roster.seats(for: "a"), [PlayerID(0), PlayerID(1)])
        XCTAssertEqual(roster.seats(for: "c"), [PlayerID(4)], "seat 4 was renumbered")
        XCTAssertEqual(roster.seats, [PlayerID(0), PlayerID(1), PlayerID(4)])
        XCTAssertEqual(roster.seatCount, 3)
    }

    func testRemovingTheHostPromotesTheNextDevice() {
        // Not a policy decision about who SHOULD host mid-race — just that `host`
        // stays answerable rather than dangling at a device that is gone.
        var roster = RaceRoster()
        try? roster.join("a", seats: 1)
        try? roster.join("b", seats: 1)
        roster.remove(peer: "a")
        XCTAssertEqual(roster.host, "b")
    }

    func testRemovingAnUnknownDeviceIsHarmless() {
        var roster = RaceRoster()
        try? roster.join("a", seats: 2)
        roster.remove(peer: "ghost")
        XCTAssertEqual(roster.seatCount, 2)
    }

    // MARK: - Agreeing it across devices

    func testARosterRoundTripsSoEveryPeerAgreesOnIt() {
        // The host assigns seats and sends the roster; every peer must decode the
        // identical thing, because a peer that disagrees about seat numbering
        // drives the wrong car.
        var roster = RaceRoster()
        try? roster.join("a", seats: 2)
        try? roster.join("b", seats: 1)
        roster.remove(peer: "a")
        try? roster.join("c", seats: 3)

        guard let data = try? JSONEncoder().encode(roster),
            let back = try? JSONDecoder().decode(RaceRoster.self, from: data)
        else { return XCTFail("roster did not round-trip") }
        XCTAssertEqual(back, roster)
        // Including the holes, which is the part a naive re-derivation would lose.
        XCTAssertEqual(back.seats, roster.seats)
        XCTAssertEqual(back.seats(for: "c"), [PlayerID(3), PlayerID(4), PlayerID(5)])
    }

    func testSeatNumbersMayExceedTheFieldSizeAfterChurn() {
        // Monotonic numbering means a lobby with churn issues numbers above the
        // field size — 4 cars might be seats 1, 3, 5, 7 in a 9-slot grid. Safe
        // because `Race` assigns grid slots by array INDEX, not by `rawValue`;
        // pinned here because that was discovered rather than designed, and a
        // future "optimisation" indexing slots by seat number would crash or stack
        // cars on top of each other.
        var roster = RaceRoster()
        for index in 0..<8 {
            try? roster.join("d\(index)", seats: 1)
            if index % 2 == 0 { roster.remove(peer: "d\(index)") }
        }
        XCTAssertEqual(roster.seats.map(\.rawValue), [1, 3, 5, 7])
        XCTAssertGreaterThan(roster.seats.last?.rawValue ?? 0, roster.seatCount)

        let race = Race(track: TrackLibrary.testRing(), players: roster.seats, seed: 1)
        XCTAssertEqual(race.cars.map(\.id), roster.seats)
        // Four distinct slots, none stacked, despite the gaps in the numbering.
        XCTAssertEqual(Set(race.cars.map(\.state.position)).count, 4)
    }

    func testTheRosterDrivesARealRace() {
        // End to end: the seats a roster produces must be what `Race` and
        // `LockstepClock` are built from, holes and all.
        var roster = RaceRoster()
        try? roster.join("a", seats: 2)
        try? roster.join("b", seats: 2)
        roster.remove(peer: "a")

        let race = Race(track: TrackLibrary.testRing(), players: roster.seats, seed: 3)
        XCTAssertEqual(race.cars.map(\.id), roster.seats)
        XCTAssertEqual(race.cars.count, 2)

        var clock = LockstepClock(players: roster.seats, delayTicks: 0)
        for seat in roster.seats { clock.receive(CarInputWire(.coast), for: seat, at: 0) }
        XCTAssertNotNil(clock.advance(), "the clock did not accept the roster's seats")
    }
}
