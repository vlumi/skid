import XCTest

@testable import SkidCore
@testable import SkidKit

/// The lobby handshake as a sequence of messages, without a radio. Two device
/// failures came out of this flow — a peer-name collision, then a countdown that
/// deadlocked — so the flow itself is now pinned.
final class LobbyFlowTests: XCTestCase {
    func testOnlyTheHostIsTheHostAfterARosterUpdate() {
        // A guest showing a working Start button means two devices can both try to
        // begin the race. Reported from device: the guest's Start rendered (and did
        // nothing), which is what a wrong `isHost` looks like.
        var hostRoster = RaceRoster()
        let host = "phoneA#aaaa"
        let guest = "phoneB#bbbb"
        try? hostRoster.join(host, seats: 2)
        try? hostRoster.join(guest, seats: 2)

        // What the guest receives and adopts.
        let update = RosterUpdate(roster: hostRoster)
        let received = try? XCTUnwrap(RosterUpdate(bytes: update.encoded)).roster
        let adopted = try? XCTUnwrap(received)

        XCTAssertEqual(adopted?.host, host, "the roster's first entry must be the host")
        XCTAssertNotEqual(adopted?.host, guest, "the guest would render a Start button")
        // And both devices agree on who drives what.
        XCTAssertEqual(adopted?.seats(for: host), [PlayerID(0), PlayerID(1)])
        XCTAssertEqual(adopted?.seats(for: guest), [PlayerID(2), PlayerID(3)])
        XCTAssertEqual(adopted?.seatCount, 4)
    }

    func testAGuestWithNoRosterYetIsNotTheHost() {
        // Before the first RosterUpdate the guest's roster is empty. `host` is nil
        // then, so `isHost` must be false rather than accidentally true.
        let empty = RaceRoster()
        XCTAssertNil(empty.host)
        XCTAssertNotEqual(empty.host, "anybody#0000")
    }

    func testTheStartMessageCarriesEverythingBothPeersNeed() {
        // Anything missing here is a divergence at tick 1 rather than an error, so
        // the round trip is worth asserting on the exact values.
        var roster = RaceRoster()
        try? roster.join("a#1111", seats: 2)
        try? roster.join("b#2222", seats: 1)
        let start = RaceStart(
            course: .builtin("clover"), seed: 12345, roster: roster, laps: 3)

        guard let back = RaceStart(bytes: start.encoded) else {
            return XCTFail("the start message did not round-trip")
        }
        XCTAssertEqual(back, start)
        XCTAssertEqual(back.seed, 12345)
        XCTAssertEqual(back.roster.seats, roster.seats)
        if case .builtin(let id) = back.course {
            XCTAssertEqual(id, "clover")
        } else {
            XCTFail("the course changed kind in transit")
        }
    }

    func testASharedTrackTravelsAsItsCode() {
        // A guest may never have seen the host's custom track — carrying the share
        // code rather than an id is what makes that work at all.
        var roster = RaceRoster()
        try? roster.join("a#1111", seats: 1)
        let code = TrackCode.encode(TrackLibrary.layout(id: "eight") ?? TrackLayout(pieces: []))
        let start = RaceStart(
            course: .shared(code), seed: 7, roster: roster, laps: 3)
        guard let back = RaceStart(bytes: start.encoded), case .shared(let got) = back.course
        else { return XCTFail("a shared course did not survive") }
        XCTAssertEqual(got, code)
        // And it still decodes into a raceable track on the far side.
        XCTAssertNotNil(try? TrackCode.decode(got))
    }

    @MainActor
    func testTwoPlayersSitFaceToFaceByDefault() {
        // What two people actually do with a phone flat on a table: one either
        // side, each with a full-width band and their own "up". Side-by-side halves
        // each player's control room — cramped on an iPhone — and exists to cram
        // three or four players onto one screen, not because two players want it.
        XCTAssertTrue(
            CouchGame(setupFilename: "test-\(UUID().uuidString).json").faceToFace,
            "two players default to side-by-side")
    }

    @MainActor
    func testTheHostStartPathBuildsASessionAndARig() {
        // The whole hand-off, which two device sessions never got through: the
        // lobby's start message must produce a session, a rig with one band per
        // LOCAL seat, and a racing phase.
        let game = CouchGame(setupFilename: "test-\(UUID().uuidString).json")
        var roster = RaceRoster()
        let me = "hostPhone#aaaa"
        try? roster.join(me, seats: 2)
        try? roster.join("guest#bbbb", seats: 2)
        let start = RaceStart(
            course: .builtin(game.trackID), seed: 9, roster: roster, laps: 3)

        game.startNetworkedRace(start, driver: StubDriver(roster.seats(for: me)))

        XCTAssertNotNil(game.session, "no session was built")
        XCTAssertEqual(game.rig?.players.count, 2, "a band per local seat")
        // Four cars in the sim, two thumbs on this device — that split is the point.
        XCTAssertEqual(game.session?.race.cars.count, 4)
        XCTAssertEqual(game.session?.started, true, "a networked race must not wait for a tap")
    }

    private final class StubDriver: NetworkedRaceDriver {
        private let seats: [PlayerID]
        let isRaceHost: Bool
        init(_ seats: [PlayerID], host: Bool = true) {
            self.seats = seats
            isRaceHost = host
        }
        var mySeats: [PlayerID] { seats }
        var generation: Int { 0 }
        func remoteInput(for seat: PlayerID) -> CarInput { .coast }
        func broadcast(_ race: Race) {}
        func publish(_ inputs: [PlayerID: CarInput]) {}
        func view(advancedBy dt: TimeInterval) -> RaceSnapshot? { nil }
    }

    func testAMalformedLobbyMessageIsRejected() {
        XCTAssertNil(RaceStart(bytes: []))
        XCTAssertNil(RaceStart(bytes: [200]))
        XCTAssertNil(RaceStart(bytes: [200, 1, 2, 3]))
        XCTAssertNil(RosterUpdate(bytes: [202, 9]))
        XCTAssertNil(JoinRequest(bytes: [201, 9]))
        // A lobby message must not be mistaken for a different kind.
        var roster = RaceRoster()
        try? roster.join("a#1111", seats: 1)
        let update = RosterUpdate(roster: roster).encoded
        XCTAssertNil(RaceStart(bytes: update), "a roster decoded as a start")
        XCTAssertNil(JoinRequest(bytes: update), "a roster decoded as a join request")
    }

    @MainActor
    func testEveryPhysicsInputComesFromTheHostNotTheDevice() {
        // **The desync, found after five device sessions.** Each device raced with its
        // OWN persisted tuning — 19 physics values behind a tuning panel. Any value
        // nudged on either phone made the cars
        // physically different, so the sims diverged from the first tick whose input is
        // actually applied. That is exactly what was measured: a repeatable desync at
        // tick 182, which is `countdownTicks + delayTicks`, with everything before it
        // masked because input is locked to coast during the countdown.
        //
        // The rule: anything the SIMULATION reads comes from the host's start message.
        // Local settings stay local to things only this screen sees.
        let game = CouchGame(setupFilename: "test-\(UUID().uuidString).json")
        // A device with deliberately unusual local settings — the state that broke it.
        // **The device's own tuning must not reach the sim.** Rather than mutate the
        // live `@AppStorage` settings — which are one shared `UserDefaults` and leaked
        // into two unrelated tests when I tried — this asserts the wiring directly:
        // whatever the host sent is what the race runs, and it is NOT this device's.

        var roster = RaceRoster()
        let me = "guest#bbbb"
        try? roster.join("host#aaaa", seats: 1)
        try? roster.join(me, seats: 1)

        // The host's message carries the host's physics, which differ from ours.
        var hostTuning = CarTuning()
        hostTuning.turnRate += 1.5
        hostTuning.gripScale += 0.3
        let start = RaceStart(
            course: .builtin(game.trackID), seed: 9, roster: roster, laps: 3,
            tuning: hostTuning)
        game.startNetworkedRace(start, driver: StubDriver(roster.seats(for: me)))

        guard let session = game.session else { return XCTFail("no session was built") }
        XCTAssertEqual(
            session.race.tuning, hostTuning,
            "the guest raced with its OWN tuning; the cars were physically different")
        // The host sent a deliberately non-default tuning, so if the device's own
        // (default) tuning had been used instead, these would differ.
        XCTAssertNotEqual(hostTuning, CarTuning(), "the test's host tuning is not distinctive")
        XCTAssertEqual(session.race.tuning.turnRate, hostTuning.turnRate, accuracy: 1e-9)
    }

    func testTheStartMessageCarriesTheWholePhysicsPicture() {
        // A round trip over the wire, so nothing silently fails to encode. Anything
        // missing here is a divergence rather than an error, which is the worst kind of
        // bug to find — it took five device sessions to find the last one.
        var roster = RaceRoster()
        try? roster.join("a#1111", seats: 2)
        var tuning = CarTuning()
        tuning.engineAccel += 123
        tuning.aimFlipBoost += 0.5
        let start = RaceStart(
            course: .builtin("clover"), seed: 42, roster: roster, laps: 5, tuning: tuning)

        guard let back = RaceStart(bytes: start.encoded) else {
            return XCTFail("the start message did not round-trip")
        }
        XCTAssertEqual(back, start)
        XCTAssertEqual(back.tuning, tuning, "the physics did not survive the wire")
        XCTAssertEqual(back.laps, 5)
    }

    func testAJoinRequestCarriesTheSeatCountToTheHost() {
        // **The message that seats a player**, and it was untested in both
        // directions — Codecov caught that, and it matters: the host builds the
        // roster from this number, and a guest silently never appearing is the
        // failure that already cost a device session (the peer-name collision).
        for seats in 1...RaceRoster.maxSeatsPerDevice {
            let request = JoinRequest(seats: seats)
            guard let back = JoinRequest(bytes: request.encoded) else {
                return XCTFail("a request for \(seats) seats did not round-trip")
            }
            XCTAssertEqual(back.seats, seats)
            XCTAssertEqual(back, request)
        }
        // End to end: the number a guest sends is the number the host seats.
        var roster = RaceRoster()
        try? roster.join("host#aaaa", seats: 1)
        guard let decoded = JoinRequest(bytes: JoinRequest(seats: 3).encoded) else {
            return XCTFail("no request")
        }
        let assigned = try? roster.join("guest#bbbb", seats: decoded.seats)
        XCTAssertEqual(assigned?.count, 3)
        XCTAssertEqual(roster.seatCount, 4)
    }

    func testAJoinRequestIsDistinctFromTheOtherLobbyMessages() {
        // Three lobby messages share one receive path, so a tag collision would
        // route a join into the roster decoder or vice versa.
        var roster = RaceRoster()
        try? roster.join("a#1111", seats: 1)
        let join = JoinRequest(seats: 2).encoded
        let update = RosterUpdate(roster: roster).encoded
        let start = RaceStart(
            course: .builtin("small"), seed: 1, roster: roster, laps: 3
        ).encoded

        // **The tags themselves must differ.** Decoding alone is a weak check —
        // sabotage proved it: colliding the join and roster tags still passed,
        // because a `{seats:}` payload does not parse as a roster regardless. The
        // shared receive path dispatches on the tag byte, so that is what to pin.
        let tags = [join[0], update[0], start[0]]
        XCTAssertEqual(Set(tags).count, 3, "two lobby messages share a tag byte")
        // Lobby tags stay clear of the per-tick tags (input 1, snapshot 3), which
        // travel the same channel.
        XCTAssertTrue(tags.allSatisfy { $0 >= 200 }, "a lobby tag entered the per-tick range")

        XCTAssertNil(RosterUpdate(bytes: join), "a join decoded as a roster")
        XCTAssertNil(RaceStart(bytes: join), "a join decoded as a start")
        XCTAssertNil(JoinRequest(bytes: update), "a roster decoded as a join")
        XCTAssertNil(JoinRequest(bytes: start), "a start decoded as a join")
        // And an absurd seat count survives the wire unchanged — validation is the
        // roster's job (it refuses with a reason the lobby shows), not the codec's,
        // so the codec must not quietly "fix" it.
        XCTAssertEqual(JoinRequest(bytes: JoinRequest(seats: 99).encoded)?.seats, 99)
        var full = RaceRoster()
        XCTAssertThrowsError(try full.join("greedy#0000", seats: 99))
    }
}
