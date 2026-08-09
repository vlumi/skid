import XCTest

@testable import SkidCore

/// **Two devices racing, in one process.** The whole lockstep loop — thumbs to
/// packet to clock to sim to hash to comparison — with the network replaced by an
/// array of bytes. Everything the spike will do on two phones happens here first,
/// which is what makes a divergence on device attributable to the transport rather
/// than to this logic.
final class NetworkedRaceTests: XCTestCase {
    /// A pair of devices wired to each other, with a controllable link.
    private struct Link {
        var a: NetworkedRace
        var b: NetworkedRace
        var raceA: Race
        var raceB: Race
        /// Packets to drop, by the tick they were sent on.
        var dropOnA: Set<Tick> = []
        var dropOnB: Set<Tick> = []

        init(seatsA: Int = 2, seatsB: Int = 2, delay: Int = 2, seed: UInt64 = 5) {
            var roster = RaceRoster()
            try? roster.join("a", seats: seatsA)
            try? roster.join("b", seats: seatsB)
            a = NetworkedRace(roster: roster, me: "a", delayTicks: delay)
            b = NetworkedRace(roster: roster, me: "b", delayTicks: delay)
            let track = TrackLibrary.testRing()
            raceA = Race(track: track, players: roster.seats, seed: seed)
            raceB = Race(track: track, players: roster.seats, seed: seed)
        }

        /// One frame: both devices read thumbs, exchange, then simulate whatever
        /// the clock releases. Returns the hashes each device produced.
        mutating func frame(tick: Tick, script: (PlayerID, Tick) -> CarInput) -> (
            a: [UInt64], b: [UInt64]
        ) {
            var inputsA: [PlayerID: CarInput] = [:]
            for seat in a.localSeats { inputsA[seat] = script(seat, tick) }
            var inputsB: [PlayerID: CarInput] = [:]
            for seat in b.localSeats { inputsB[seat] = script(seat, tick) }

            let fromA = a.send(inputsA, at: tick)
            let fromB = b.send(inputsB, at: tick)
            if !dropOnB.contains(tick) { b.receive(fromA, from: "a") }
            if !dropOnA.contains(tick) { a.receive(fromB, from: "b") }

            // Drained separately, then the hash reports are exchanged — Swift's
            // exclusivity rules forbid handing two of `self`'s fields to one
            // function as `inout`, and copying would hide a real aliasing bug.
            let (hashesA, reportsA) = Self.drain(&a, &raceA)
            let (hashesB, reportsB) = Self.drain(&b, &raceB)
            for report in reportsA { b.receive(report, from: "a") }
            for report in reportsB { a.receive(report, from: "b") }
            return (hashesA, hashesB)
        }

        /// Simulate every tick the clock releases, collecting the hash reports the
        /// transport would send.
        private static func drain(_ net: inout NetworkedRace, _ race: inout Race) -> (
            hashes: [UInt64], reports: [[UInt8]]
        ) {
            var hashes: [UInt64] = []
            var reports: [[UInt8]] = []
            while let inputs = net.nextTick() {
                race.advance(inputs: inputs)
                reports.append(net.report(hash: race.stateHash, at: race.tick))
                hashes.append(race.stateHash)
            }
            return (hashes, reports)
        }
    }

    private func script(_ seat: PlayerID, _ tick: Tick) -> CarInput {
        CarInput(
            steer: sin(Double(tick) / 35 + Double(seat.rawValue)),
            throttle: tick % 200 < 170 ? 1 : -1)
    }

    // MARK: - The thing that has to work

    func testTwoDevicesSimulateTheIdenticalRace() {
        // The headline claim. Four cars, two devices, two thumbs each — and both
        // devices reach the same state every tick, with neither having sent a car
        // position to the other.
        var link = Link()
        var hashesA: [UInt64] = []
        var hashesB: [UInt64] = []
        for tick in 0..<600 {
            let (a, b) = link.frame(tick: tick, script: script)
            hashesA += a
            hashesB += b
        }
        XCTAssertGreaterThan(hashesA.count, 500, "the race barely advanced")
        XCTAssertEqual(hashesA, hashesB, "the two devices diverged")
        XCTAssertNil(link.a.divergence)
        XCTAssertNil(link.b.divergence)
        // And the cars really drove — a stalled race would pass the above trivially.
        XCTAssertNotEqual(
            link.raceA.cars[0].state.position, TrackLibrary.testRing().startSlots[0])
    }

    func testANetworkedRaceMatchesAPurelyLocalOne() {
        // Stronger than the two devices agreeing with each other: they must agree
        // with the sim run directly, so the networking adds nothing and drops
        // nothing. Quantised on both sides, since that is what the wire does.
        var link = Link(delay: 2)
        var networked: [UInt64] = []
        for tick in 0..<400 { networked += link.frame(tick: tick, script: script).a }

        var local = Race(track: TrackLibrary.testRing(), players: link.a.roster.seats, seed: 5)
        var expected: [UInt64] = []
        for tick in 0..<networked.count {
            var inputs: [PlayerID: CarInput] = [:]
            for seat in link.a.roster.seats { inputs[seat] = script(seat, tick).quantised }
            local.advance(inputs: inputs)
            expected.append(local.stateHash)
        }
        if let tick = Array(zip(expected, networked)).firstIndex(where: { $0 != $1 }) {
            XCTFail("networking changed the race at tick \(tick)")
        }
        XCTAssertEqual(networked, expected)
    }

    func testTheDelayBufferCostsLagButNotCorrectness() {
        // Whatever `delayTicks` is set to, the race must be the same race — the
        // knob buys tolerance for late packets, not a different simulation. It is
        // the one parameter the spike tunes on device, so it must be safe to change.
        var hashesByDelay: [Int: [UInt64]] = [:]
        for delay in [0, 2, 4] {
            var link = Link(delay: delay)
            var hashes: [UInt64] = []
            for tick in 0..<300 { hashes += link.frame(tick: tick, script: script).a }
            hashesByDelay[delay] = hashes
        }
        let shortest = hashesByDelay[4]?.count ?? 0
        XCTAssertGreaterThan(shortest, 250)
        for delay in [0, 2] {
            XCTAssertEqual(
                Array(hashesByDelay[delay]?.prefix(shortest) ?? []),
                Array(hashesByDelay[4]?.prefix(shortest) ?? []),
                "delay \(delay) simulated a different race than delay 4")
        }
        // And a bigger buffer really does run further behind, which is the cost.
        XCTAssertGreaterThan(
            hashesByDelay[0]?.count ?? 0, hashesByDelay[4]?.count ?? 0,
            "the delay buffer cost nothing, so it is not doing anything")
    }

    // MARK: - The failure modes, provoked deliberately

    func testASingleLostPacketDoesNotDivergeTheRace() {
        // Redundancy repairs it, and neither device notices. This is what "loss
        // becomes lag, not teleporting cars" means in practice.
        var link = Link(delay: 2)
        link.dropOnB = [50, 120, 121]  // one lost, then two consecutive
        var hashesA: [UInt64] = []
        var hashesB: [UInt64] = []
        for tick in 0..<400 {
            let (a, b) = link.frame(tick: tick, script: script)
            hashesA += a
            hashesB += b
        }
        XCTAssertEqual(hashesA, hashesB, "packet loss diverged the race")
        XCTAssertNil(link.b.divergence)
        XCTAssertGreaterThan(hashesB.count, 350, "the race stalled instead of recovering")
    }

    func testADroppedPeerStallsBothDevicesRatherThanForkingThem() {
        // The correct failure mode for a shared race: everyone waits. A device that
        // kept going alone would be watching a different race from everybody else,
        // which is worse than a frozen screen.
        var link = Link(delay: 0)
        var hashes: [UInt64] = []
        for tick in 0..<100 { hashes += link.frame(tick: tick, script: script).a }
        let before = hashes.count
        XCTAssertGreaterThan(before, 90)

        // Device B walks out of range: A keeps sending, nothing comes back.
        for tick in 100..<160 {
            var inputs: [PlayerID: CarInput] = [:]
            for seat in link.a.localSeats { inputs[seat] = script(seat, tick) }
            _ = link.a.send(inputs, at: tick)
            while let next = link.a.nextTick() {
                link.raceA.advance(inputs: next)
                hashes.append(0)
            }
        }
        XCTAssertEqual(hashes.count, before, "the race ran on without a peer's input")
        // And it can say who it is waiting for.
        link.a.peerLeft("b")
        XCTAssertEqual(link.a.stalledOn, Set(link.a.roster.seats(for: "b")))
        guard case .waitingForInput(_, let missing) = link.a.stall else {
            return XCTFail("expected a named stall, got \(String(describing: link.a.stall))")
        }
        XCTAssertEqual(missing, link.a.roster.seats(for: "b"))
    }

    func testARealDivergenceIsCaughtAndNamed() {
        // The spike's core measurement. One device's sim is nudged — as a libm
        // difference would nudge it — and the watch must name the tick.
        var link = Link(delay: 0)
        for tick in 0..<100 {
            _ = link.frame(tick: tick, script: script)
            if tick == 60 { link.raceB.cars[0].state.position.x += 1 }
        }
        XCTAssertNotNil(link.a.divergence, "a real divergence went unreported")
        XCTAssertEqual(link.a.divergence?.tick, 62)
        XCTAssertEqual(link.a.divergence?.peer, "b")
    }

    // MARK: - Hostile and malformed input

    func testGarbageFromAPeerIsDroppedNotFatal()
        throws
    {
        // 60 packets a second from another device: a corrupt one must not be able
        // to end the race. Fuzzed rather than hand-picked, because the interesting
        // malformed packets are the ones I would not think to write.
        var link = Link()
        var rng = SeededRNG(seed: 99)
        for length in 0..<40 {
            let bytes = (0..<length).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            XCTAssertFalse(link.a.receive(bytes, from: "b") && length < 5)
        }
        // And the race still runs afterwards.
        var hashes: [UInt64] = []
        for tick in 0..<100 { hashes += link.frame(tick: tick, script: script).a }
        XCTAssertGreaterThan(hashes.count, 90)
    }

    func testAMessageFromOutsideTheRosterIsIgnored() {
        // An uninvited device must not be able to inject inputs — it owns no seat,
        // so there is nothing legitimate it could be saying on this channel.
        //
        // The packet has to be one the roster check is the ONLY thing rejecting.
        // Replaying `a`'s own bytes proves nothing: they carry a's seat count, so
        // the packet decoder rejects them against a different roster and the test
        // passes without the membership check existing at all. So this forges a
        // WELL-FORMED packet for seats the gatecrasher does not own.
        var link = Link()
        let victim = link.b.localSeats
        let coasting = Dictionary(uniqueKeysWithValues: victim.map { ($0, CarInputWire(.coast)) })
        let forged = LockstepClock.Packet(tick: 0, inputs: [coasting]).encoded(roster: victim)
        XCTAssertNotNil(
            LockstepClock.Packet(bytes: forged, roster: victim), "the forgery is malformed")
        XCTAssertFalse(
            link.a.receive([1] + forged, from: "gatecrasher"), "an outsider was believed")
        // And the same bytes from the device that DOES own those seats are accepted,
        // so the rejection is about membership rather than the payload.
        XCTAssertTrue(link.a.receive([1] + forged, from: "b"))
    }

    func testOurOwnEchoIsIgnored() {
        // MultipeerConnectivity does not echo, but a broadcast transport might, and
        // applying our own packet twice must be harmless rather than a double-count.
        var link = Link()
        let mine = link.a.send([:], at: 0)
        XCTAssertFalse(link.a.receive(mine, from: "a"))
    }

    func testATruncatedHashReportIsRejected() {
        // A clipped hash message must be dropped rather than read from whatever
        // bytes happen to follow — a garbage hash would report a divergence that
        // never happened, which on the spike is worse than silence.
        var link = Link()
        let good = link.a.report(hash: 0xDEAD_BEEF, at: 7)
        XCTAssertTrue(link.b.receive(good, from: "a"))
        XCTAssertFalse(
            link.b.receive(Array(good.dropLast()), from: "a"), "truncated hash believed")
        XCTAssertFalse(link.b.receive(good + [0], from: "a"), "over-long hash believed")
        XCTAssertFalse(link.b.receive([2], from: "a"), "empty hash body believed")
    }

    func testAnUnknownMessageKindIsIgnoredRatherThanFatal() {
        // Forward compatibility: a future build sending a new message kind must not
        // break this one, so an unrecognised tag is skipped.
        var link = Link()
        XCTAssertFalse(link.a.receive([99, 1, 2, 3], from: "b"))
    }

    // MARK: - The wire

    func testTheWholeFrameFitsComfortablyInADatagram() {
        // Two messages per device per tick at 60 Hz. Worth pinning: if this ever
        // needed fragmenting, the transport's failure modes would multiply.
        var link = Link(seatsA: 4, seatsB: 4)
        var biggest = 0
        for tick in 0..<10 {
            var inputs: [PlayerID: CarInput] = [:]
            for seat in link.a.localSeats { inputs[seat] = script(seat, tick) }
            biggest = max(biggest, link.a.send(inputs, at: tick).count)
        }
        XCTAssertLessThan(biggest, 128, "an input packet outgrew a datagram")
        XCTAssertEqual(link.a.report(hash: 12345, at: 1).count, 13, "tag + tick + hash")
    }
}
