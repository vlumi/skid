import XCTest

@testable import SkidCore

/// The failure modes, which are the whole reason lockstep needs testing: packet
/// loss, a peer that drops, reordered arrivals, and the delay buffer that turns
/// the first of those into lag instead of a freeze.
final class LockstepTests: XCTestCase {
    private let seats = [PlayerID(0), PlayerID(1)]

    private func wire(_ steer: Double) -> CarInputWire {
        CarInputWire(CarInput(steer: steer))
    }

    /// Every seat's input for one tick, as a packet with no redundancy.
    private func packet(tick: Tick, steer: Double = 0) -> LockstepClock.Packet {
        var seatInputs: [PlayerID: CarInputWire] = [:]
        for seat in seats { seatInputs[seat] = wire(steer) }
        return LockstepClock.Packet(tick: tick, inputs: [seatInputs])
    }

    /// A packet carrying `Packet.history` ticks redundantly, as the real sender
    /// does — the newest tick plus the ones before it.
    private func redundantPacket(tick: Tick) -> LockstepClock.Packet {
        var frames: [[PlayerID: CarInputWire]] = []
        for offset in 0..<LockstepClock.Packet.history where tick - offset >= 0 {
            var seatInputs: [PlayerID: CarInputWire] = [:]
            for seat in seats { seatInputs[seat] = wire(Double(tick - offset) / 100) }
            frames.append(seatInputs)
        }
        return LockstepClock.Packet(tick: tick, inputs: frames)
    }

    // MARK: - A tick cannot run early

    func testATickWaitsForEverySeat() {
        var clock = LockstepClock(players: seats, delayTicks: 0)
        clock.receive(wire(1), for: seats[0], at: 0)
        XCTAssertFalse(clock.canAdvance, "advanced with one seat missing")
        XCTAssertNil(clock.advance(), "a missing input must not become a coast")
        XCTAssertEqual(clock.stall, .waitingForInput(tick: 0, missing: [seats[1]]))

        clock.receive(wire(-1), for: seats[1], at: 0)
        XCTAssertTrue(clock.canAdvance)
        XCTAssertEqual(clock.advance()?.count, 2)
        XCTAssertEqual(clock.tick, 1)
    }

    func testAMissingInputIsNeverACoast() {
        // The most dangerous shortcut available here: substituting `.coast` for a
        // late input keeps the frame rate up and silently forks the race, because
        // the peer that DID receive it simulates something else. Lockstep must
        // stall instead, so this asserts the absence of that convenience.
        var clock = LockstepClock(players: seats, delayTicks: 0)
        for _ in 0..<10 { XCTAssertNil(clock.advance()) }
        XCTAssertEqual(clock.tick, 0, "the clock crept forward without inputs")
    }

    func testTicksAreSimulatedInOrder() {
        // Tick 5 arriving first must not let the sim skip ahead to it.
        var clock = LockstepClock(players: seats, delayTicks: 0)
        clock.receive(packet(tick: 5))
        XCTAssertFalse(clock.canAdvance)
        XCTAssertEqual(clock.tick, 0)
        clock.receive(packet(tick: 0))
        XCTAssertNotNil(clock.advance())
        XCTAssertEqual(clock.tick, 1, "the clock jumped past unsimulated ticks")
    }

    // MARK: - The delay buffer

    func testTheDelayBufferHoldsATickBackUntilItHasSlack() {
        // With delay 2 the sim runs two ticks behind the newest input, so a late
        // packet has time to land. Everything for tick 0 is present here and it
        // still must not run.
        var clock = LockstepClock(players: seats, delayTicks: 2)
        clock.receive(packet(tick: 0))
        XCTAssertFalse(clock.canAdvance, "ran without the buffer's slack")
        XCTAssertEqual(clock.stall, .buffering(tick: 0, ticksBehind: 0))

        clock.receive(packet(tick: 1))
        XCTAssertFalse(clock.canAdvance)
        clock.receive(packet(tick: 2))
        XCTAssertTrue(clock.canAdvance, "buffer never released the tick")
        XCTAssertNotNil(clock.advance())
    }

    func testZeroDelayRunsAsSoonAsInputsArrive() {
        // Legal, and the configuration with the least lag and the least tolerance
        // for a late packet. Worth pinning because it is the baseline the device
        // tuning will be compared against.
        var clock = LockstepClock(players: seats, delayTicks: 0)
        clock.receive(packet(tick: 0))
        XCTAssertTrue(clock.canAdvance)
    }

    func testANegativeDelayIsClampedNotHonoured() {
        // A negative buffer would mean running AHEAD of received input, which is
        // prediction — a different design, and not one this clock implements.
        XCTAssertEqual(LockstepClock(players: seats, delayTicks: -5).delayTicks, 0)
    }

    // MARK: - Packet loss

    func testASingleLostPacketIsRepairedByTheNextOne() {
        // The property the whole redundancy scheme exists for: drop a packet
        // entirely and the race must still run every tick, with no gap and no
        // retransmission request.
        var clock = LockstepClock(players: seats, delayTicks: 0)
        for tick in 0..<12 where tick != 5 {  // packet 5 never arrives
            clock.receive(redundantPacket(tick: tick))
        }
        var simulated: [Tick] = []
        while clock.advance() != nil { simulated.append(clock.tick - 1) }
        XCTAssertEqual(simulated, Array(0..<12), "a lost packet left a hole")
    }

    func testTwoConsecutiveLossesAreSurvivedAndThreeAreNot() {
        // `Packet.history` is 3, so the design's claim is exactly this: two
        // consecutive losses are repaired, and the third is where it stalls. Both
        // halves asserted, because the limit is the useful part of the claim.
        XCTAssertEqual(LockstepClock.Packet.history, 3)

        var survives = LockstepClock(players: seats, delayTicks: 0)
        for tick in 0..<12 where tick != 5 && tick != 6 {
            survives.receive(redundantPacket(tick: tick))
        }
        var ticks = 0
        while survives.advance() != nil { ticks += 1 }
        XCTAssertEqual(ticks, 12, "two consecutive losses should be repairable")

        var stalls = LockstepClock(players: seats, delayTicks: 0)
        for tick in 0..<12 where tick < 4 || tick > 6 {  // 4, 5, 6 all lost
            stalls.receive(redundantPacket(tick: tick))
        }
        var before = 0
        while stalls.advance() != nil { before += 1 }
        XCTAssertEqual(before, 4, "three consecutive losses must stall at tick 4")
        XCTAssertEqual(stalls.stall, .waitingForInput(tick: 4, missing: seats))
    }

    func testRedundantCopiesDoNotOverwriteWhatArrivedFirst() {
        // Idempotence is what makes redundancy safe. If a later copy could
        // replace an earlier one, two peers receiving the copies in different
        // orders would simulate different races — a divergence caused by the
        // repair mechanism itself.
        var clock = LockstepClock(players: seats, delayTicks: 0)
        clock.receive(wire(1), for: seats[0], at: 0)
        clock.receive(wire(-1), for: seats[0], at: 0)  // a contradicting copy
        clock.receive(wire(0), for: seats[1], at: 0)
        let inputs = clock.advance()
        XCTAssertEqual(inputs?[seats[0]]?.steer, 1, "a later copy overwrote the first")
    }

    func testInputForAnAlreadySimulatedTickIsIgnored() {
        // The past is settled. A redundant packet arriving after its tick ran
        // must not be buffered — it would sit in memory forever and, worse,
        // suggest the tick could be re-run.
        var clock = LockstepClock(players: seats, delayTicks: 0)
        clock.receive(packet(tick: 0))
        XCTAssertNotNil(clock.advance())
        clock.receive(packet(tick: 0))
        XCTAssertEqual(clock.tick, 1)
        // Asserting on the BUFFER, not on `bufferedTicks`: that counter is derived
        // from `newestReceived`, which a stale packet does not move, so it reads 0
        // whether or not the stale input lodged. This test was vacuous until the
        // sabotage pass said so.
        XCTAssertEqual(clock.heldTicks, [], "a settled tick was re-buffered")
        // A redundant packet whose newest tick is live must still land, though —
        // the repair mechanism depends on it.
        clock.receive(redundantPacket(tick: 3))
        XCTAssertEqual(clock.heldTicks, [1, 2, 3], "live ticks from a redundant packet were lost")
    }

    // MARK: - A peer that drops

    func testADroppedPeerStallsTheRaceAtANamedTick() {
        // The correct failure mode for a shared race, and the one the spike must
        // provoke deliberately: everyone waits, and the clock can say who for.
        var clock = LockstepClock(players: seats, delayTicks: 0)
        for tick in 0..<5 { clock.receive(packet(tick: tick)) }
        // Seat 1's device walks out of range: only seat 0 keeps sending.
        for tick in 5..<10 { clock.receive(wire(0), for: seats[0], at: tick) }

        var ran = 0
        while clock.advance() != nil { ran += 1 }
        XCTAssertEqual(ran, 5, "the race ran past a dropped peer")
        XCTAssertEqual(clock.stall, .waitingForInput(tick: 5, missing: [seats[1]]))
    }

    func testASoloRaceNeverWaitsOnAnyoneElse() {
        // One device, one seat: the degenerate case must behave like today's local
        // race rather than waiting for an absent peer. It still stalls once it runs
        // OUT of input — every clock does, that is what "lockstep" means — so the
        // claim is that it never waits on a seat it does not own.
        let solo = PlayerID(0)
        var clock = LockstepClock(players: [solo], delayTicks: 0)
        for tick in 0..<30 {
            clock.receive(wire(0), for: solo, at: tick)
            XCTAssertNotNil(clock.advance(), "solo clock stalled with its own input in hand")
        }
        XCTAssertEqual(clock.tick, 30)
        // And when it does stall, it is waiting on itself — nobody else exists.
        XCTAssertEqual(clock.stall, .waitingForInput(tick: 30, missing: [solo]))
    }

    func testStallIsNilWhenTheClockCanRun() {
        // `stall` answers "why are we not moving" and must say nothing when we ARE
        // moving — chrome keyed off it would otherwise flash "waiting for players"
        // between every tick.
        var clock = LockstepClock(players: seats, delayTicks: 0)
        clock.receive(packet(tick: 0))
        XCTAssertTrue(clock.canAdvance)
        XCTAssertNil(clock.stall, "a runnable clock reported a stall")
    }

    func testASenderSendsCoastForSeatsItDoesNotOwn() {
        // `encoded(roster:)` fills a missing seat with coast. Safe only because a
        // SENDER always has its own seats' input, so a hole means "not mine" — and
        // the roster passed in is the sender's own. Pinned because the same
        // fallback on the RECEIVING side would silently fork the race.
        let mine = seats[0]
        let packet = LockstepClock.Packet(tick: 3, inputs: [[mine: wire(0.5)]])
        let bytes = packet.encoded(roster: seats)
        let back = LockstepClock.Packet(bytes: bytes, roster: seats)
        XCTAssertEqual(back?.inputs.first?[mine]?.input.steer ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(back?.inputs.first?[seats[1]], CarInputWire(.coast), "absent seat not coast")
    }

    func testASeatlessClockAdvancesWithoutInput() {
        // The degenerate roster: no seats, so there is nothing to wait for. Worth
        // pinning because `advance()` reads a pending entry that will not exist,
        // and the empty case must return an empty input set rather than trap.
        var clock = LockstepClock(players: [], delayTicks: 0)
        clock.receive(LockstepClock.Packet(tick: 0, inputs: [[:]]))
        XCTAssertEqual(clock.advance()?.isEmpty, true)
        XCTAssertEqual(clock.tick, 1)
    }

    // MARK: - Health readout

    func testBufferedTicksReportsHowFarAheadTheInputIs() {
        var clock = LockstepClock(players: seats, delayTicks: 0)
        XCTAssertEqual(clock.bufferedTicks, 0, "starved clock claims a buffer")
        for tick in 0..<5 { clock.receive(packet(tick: tick)) }
        XCTAssertEqual(clock.bufferedTicks, 5)
        _ = clock.advance()
        XCTAssertEqual(clock.bufferedTicks, 4, "consuming a tick did not drain the buffer")
    }

    // MARK: - The wire form

    func testAPacketIsSmallOnTheWire() {
        // `Codable` is not a wire format, measured rather than assumed: the same
        // packet is 438 bytes of JSON because every seat id is a dictionary key on
        // every tick. Positional-against-roster is what makes it 4 + 4n bytes.
        let packet = redundantPacket(tick: 1234)
        let bytes = packet.encoded(roster: seats)
        let payload = seats.count * LockstepClock.Packet.history * CarInputWire.byteCount
        XCTAssertEqual(bytes.count, 5 + payload, "4 bytes of tick, 1 of seat count, then inputs")
        XCTAssertEqual(bytes.count, 29, "two seats, three ticks of redundancy")

        // Well under a datagram, so redundancy costs nothing structural: even a
        // nine-seat field with three ticks of history fits comfortably.
        let full = (0..<9).map { PlayerID($0) }
        var frames: [[PlayerID: CarInputWire]] = []
        for _ in 0..<LockstepClock.Packet.history {
            frames.append(Dictionary(uniqueKeysWithValues: full.map { ($0, wire(0.5)) }))
        }
        let big = LockstepClock.Packet(tick: 9999, inputs: frames).encoded(roster: full)
        XCTAssertEqual(big.count, 5 + 9 * 3 * 4)
        XCTAssertLessThan(big.count, 512, "a full field must fit a small datagram")
    }

    func testAPacketRoundTripsThroughItsBytes() {
        let packet = redundantPacket(tick: 4321)
        let bytes = packet.encoded(roster: seats)
        let back = LockstepClock.Packet(bytes: bytes, roster: seats)
        XCTAssertEqual(back, packet)
        XCTAssertEqual(back?.tick, 4321)
    }

    func testAMalformedPacketIsRejectedRatherThanGuessed() {
        // A peer sending garbage — or a roster mismatch — must be dropped, not
        // partially believed. Truncation is the realistic case: a clipped datagram
        // that still parses would inject invented inputs into the race.
        let bytes = redundantPacket(tick: 7).encoded(roster: seats)
        XCTAssertNil(LockstepClock.Packet(bytes: Array(bytes.dropLast()), roster: seats))
        XCTAssertNil(LockstepClock.Packet(bytes: Array(bytes.prefix(3)), roster: seats))
        XCTAssertNil(LockstepClock.Packet(bytes: bytes, roster: []))
        // **A roster of the wrong SIZE is the dangerous one.** 24 bytes of payload
        // divides evenly by a 3-seat roster as well as a 2-seat one, so length
        // alone let this decode cleanly and invent inputs for a seat that never
        // sent any. The packet states its own seat count for exactly this.
        let threeSeats = [PlayerID(0), PlayerID(1), PlayerID(2)]
        XCTAssertNil(LockstepClock.Packet(bytes: bytes, roster: threeSeats))
        XCTAssertNil(LockstepClock.Packet(bytes: bytes, roster: [PlayerID(0)]))
    }

    func testTheRosterNamesSeatsOnceRatherThanPerTick() {
        // The saving is the point: the same bytes decoded against a DIFFERENT
        // roster yield different seats, which is what "positional" means and why
        // both peers must agree the roster at join time.
        let bytes = packet(tick: 3, steer: 0.5).encoded(roster: seats)
        let renamed = [PlayerID(7), PlayerID(8)]
        let back = LockstepClock.Packet(bytes: bytes, roster: renamed)
        XCTAssertEqual(back?.inputs.first?.keys.sorted(), renamed)
        XCTAssertEqual(back?.inputs.first?[renamed[0]]?.input.steer ?? 0, 0.5, accuracy: 0.01)
    }

    // MARK: - Driving a real race through it

    func testARaceDrivenThroughTheClockMatchesOneDrivenDirectly() {
        // The clock must not change the race — it only decides when a tick may
        // run. Same inputs through both paths, compared by hash sequence, so a
        // difference names its tick.
        let track = TrackLibrary.testRing()
        let script = { (seat: PlayerID, tick: Tick) in
            CarInput(steer: sin(Double(tick) / 40 + Double(seat.rawValue)), throttle: 1)
                .quantised
        }

        var direct = Race(track: track, players: seats, seed: 4)
        var expected: [UInt64] = []
        for _ in 0..<300 {
            var inputs: [PlayerID: CarInput] = [:]
            for seat in seats { inputs[seat] = script(seat, direct.tick) }
            direct.advance(inputs: inputs)
            expected.append(direct.stateHash)
        }

        var clock = LockstepClock(players: seats, delayTicks: 2)
        var networked = Race(track: track, players: seats, seed: 4)
        var got: [UInt64] = []
        // Inputs arrive a few ticks ahead, as they would with the delay buffer.
        for tick in 0..<303 {
            var seatInputs: [PlayerID: CarInputWire] = [:]
            for seat in seats { seatInputs[seat] = CarInputWire(script(seat, tick)) }
            clock.receive(LockstepClock.Packet(tick: tick, inputs: [seatInputs]))
            while got.count < 300, let inputs = clock.advance() {
                networked.advance(inputs: inputs)
                got.append(networked.stateHash)
            }
        }
        if let tick = Array(zip(expected, got)).firstIndex(where: { $0 != $1 }) {
            XCTFail("the clock changed the race at tick \(tick)")
        }
        XCTAssertEqual(got, expected)
        XCTAssertEqual(got.count, 300)
    }
}
