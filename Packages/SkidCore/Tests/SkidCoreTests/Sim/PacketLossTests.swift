import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Packet loss, taken seriously.**
///
/// The original harness dropped 3 packets in 400 and the redundancy window covered
/// 33 ms — an assumption dressed as a measurement, and it hid a real desync. A
/// phone's Wi-Fi loses far longer bursts than that.
@MainActor
final class PacketLossTests: XCTestCase {
    private let seats = [PlayerID(0), PlayerID(1)]

    private func script(_ seat: PlayerID, _ tick: Tick) -> CarInput {
        CarInput(
            steer: sin(Double(tick) / 35 + Double(seat.rawValue)),
            throttle: tick % 200 < 170 ? 1 : -1)
    }

    // MARK: - Packet loss, taken seriously

    func testAGapInPublishedTicksIsNeverMisattributed() {
        // **The desync, reported from device.** The redundancy window was built with
        // `compactMap`, so a tick that was never published SHORTENED the frame array
        // — and the wire format is positional, frame *i* meaning `tick - i`. Measured:
        // publishing 0, 1, 2 then 4 produced a packet whose "tick 3" slot carried
        // tick 2's input. The receiver applied the wrong input to tick 3, both peers
        // computed different states from the same packet, and tick 3 never
        // legitimately arrived — the constant "waiting for iPhone".
        var roster = RaceRoster()
        try? roster.join("a", seats: 1)
        var net = NetworkedRace(roster: roster, me: "a", delayTicks: 0)
        let seat = PlayerID(0)

        for tick in [0, 1, 2, 4] {  // 3 deliberately skipped
            let bytes = net.send([seat: CarInput(steer: Double(tick) / 10)], at: Tick(tick))
            guard let packet = LockstepClock.Packet(bytes: Array(bytes.dropFirst()), roster: [seat])
            else { return XCTFail("packet did not decode") }
            // Every frame must land on the tick it claims.
            for (offset, frame) in packet.inputs.enumerated() {
                let claimed = packet.tick - offset
                guard let steer = frame[seat]?.input.steer else {
                    return XCTFail("no input for the seat at tick \(claimed)")
                }
                // A published tick carries its own value; a skipped one coasts. What
                // must NEVER happen is carrying a DIFFERENT tick's value.
                let expected = claimed == 3 ? 0.0 : Double(claimed) / 10
                XCTAssertEqual(
                    steer, expected, accuracy: 0.01,
                    "tick \(claimed) carried the wrong input")
            }
        }
    }

    func testARaceSurvivesHeavyPacketLoss() {
        // My harness previously dropped 3 packets in 400. Real Wi-Fi on a phone loses
        // far more than that, and the user was right that assuming otherwise is what
        // hid the bug above. This drops a fifth of everything, in bursts.
        var roster = RaceRoster()
        try? roster.join("a", seats: 1)
        try? roster.join("b", seats: 1)
        var a = NetworkedRace(roster: roster, me: "a", delayTicks: 2)
        var b = NetworkedRace(roster: roster, me: "b", delayTicks: 2)
        var raceA = Race(track: TrackLibrary.testRing(), players: roster.seats, seed: 5)
        var raceB = Race(track: TrackLibrary.testRing(), players: roster.seats, seed: 5)
        var rng = SeededRNG(seed: 4242)

        for tick in 0..<600 {
            let fromA = a.send([PlayerID(0): script(PlayerID(0), Tick(tick))], at: Tick(tick))
            let fromB = b.send([PlayerID(1): script(PlayerID(1), Tick(tick))], at: Tick(tick))
            // 20% loss each way, independently.
            if rng.next() % 5 != 0 { b.receive(fromA, from: "a") }
            if rng.next() % 5 != 0 { a.receive(fromB, from: "b") }
            while let inputs = a.nextTick() {
                raceA.advance(inputs: inputs)
                _ = a.report(hash: raceA.stateHash, at: raceA.tick)
            }
            while let inputs = b.nextTick() {
                raceB.advance(inputs: inputs)
                _ = b.report(hash: raceB.stateHash, at: raceB.tick)
            }
        }
        // Loss costs progress — that is the honest trade — but it must NEVER cost
        // agreement. Both peers reached the same state, whatever tick they got to.
        XCTAssertEqual(raceA.tick, raceB.tick, "the peers ran to different ticks")
        XCTAssertEqual(raceA.stateHash, raceB.stateHash, "20% loss diverged the race")
        XCTAssertGreaterThan(raceA.tick, 300, "loss stopped the race entirely")
    }

    func testLossCostsProgressButNeverAgreement() {
        // **The property that matters more than any loss rate.** Measured: gapless,
        // deeply-redundant input holds full speed AND agreement through 60% loss, and
        // at 80% it falls behind — which is the correct failure. What must never
        // happen is the peers diverging, because there is no state on the wire to
        // correct them and every frame after a divergence is fiction.
        for lossPercent in [40, 60, 80] {
            var roster = RaceRoster()
            try? roster.join("a", seats: 1)
            try? roster.join("b", seats: 1)
            var a = NetworkedRace(roster: roster, me: "a", delayTicks: 2)
            var b = NetworkedRace(roster: roster, me: "b", delayTicks: 2)
            var raceA = Race(track: TrackLibrary.testRing(), players: roster.seats, seed: 5)
            var raceB = Race(track: TrackLibrary.testRing(), players: roster.seats, seed: 5)
            var rng = SeededRNG(seed: 99)
            var hashesA: [Tick: UInt64] = [:]
            var hashesB: [Tick: UInt64] = [:]

            for tick in 0..<600 {
                let fromA = a.send([PlayerID(0): script(PlayerID(0), Tick(tick))], at: Tick(tick))
                let fromB = b.send([PlayerID(1): script(PlayerID(1), Tick(tick))], at: Tick(tick))
                if Int(rng.next() % 100) >= lossPercent { b.receive(fromA, from: "a") }
                if Int(rng.next() % 100) >= lossPercent { a.receive(fromB, from: "b") }
                while let i = a.nextTick() {
                    raceA.advance(inputs: i)
                    hashesA[raceA.tick] = raceA.stateHash
                }
                while let i = b.nextTick() {
                    raceB.advance(inputs: i)
                    hashesB[raceB.tick] = raceB.stateHash
                }
            }
            // Compare every tick BOTH peers reached. One may be behind; where they
            // overlap they must agree exactly.
            // At 95% nothing advances at all, which is a correct stall but leaves no
            // shared ticks to compare — so the sweep stops at 80%, where one peer
            // falls behind and agreement still has to hold.
            let shared = Set(hashesA.keys).intersection(hashesB.keys)
            XCTAssertFalse(shared.isEmpty, "no shared ticks at \(lossPercent)% loss")
            for tick in shared.sorted() {
                XCTAssertEqual(
                    hashesA[tick], hashesB[tick],
                    "peers diverged at tick \(tick) under \(lossPercent)% loss")
            }
        }
    }

    func testRedundancyCoversARealisticBurst() {
        // Three ticks — 33 ms — was the original depth, and it was an assumption
        // dressed as a measurement. Deepening it to twenty then did NOT fix the
        // device, which is what settled the design: redundancy alone cannot repair
        // sustained loss at any depth, so input now rides the RELIABLE channel and
        // this is a head start on reordering rather than a loss budget.
        XCTAssertGreaterThanOrEqual(
            LockstepClock.Packet.history, 4, "redundancy must cover more than a frame")
        // And it stays inside one datagram for a full field, since fragmenting would
        // multiply the transport's failure modes.
        let full = (0..<9).map { PlayerID($0) }
        var frames: [[PlayerID: CarInputWire]] = []
        for _ in 0..<LockstepClock.Packet.history {
            frames.append(
                Dictionary(
                    uniqueKeysWithValues: full.map { ($0, CarInputWire(CarInput(steer: 0.5))) }))
        }
        let bytes = LockstepClock.Packet(tick: 9999, inputs: frames).encoded(roster: full)
        XCTAssertLessThan(bytes.count, 1024, "a full field's packet outgrew a datagram")
    }

    func testTwoPeersDoNotStarveEachOther() {
        // **The steady stutter, reported from device three times across two channel
        // modes** — which was the clue it was never a network problem.
        //
        // Publishing keyed off `race.tick + delayTicks`, and `race.tick` only advances
        // when the clock releases a tick, which needs the PEER's input. So a stall
        // froze our publish edge, which starved the peer, which stalled it, which
        // starved us. A mutual deadlock that breaks and re-forms with a rhythm.
        //
        // This drives both peers through the real `GameSession` loop with a link that
        // delivers everything — no loss at all — so any stalling is self-inflicted.
        var roster = RaceRoster()
        try? roster.join("host#aaaa", seats: 1)
        try? roster.join("guest#bbbb", seats: 1)
        let start = RaceStart(
            course: .builtin("small"), seed: 5, roster: roster, laps: 3, delayTicks: 2)

        let hostNet = NetworkedGame(displayName: "host#aaaa")
        let guestNet = NetworkedGame(displayName: "guest#bbbb")
        hostNet.adoptForTesting(start)
        guestNet.adoptForTesting(start)
        let host = makeSession(start, hostNet)
        let guest = makeSession(start, guestNet)

        // **With LATENCY, which is what the harness was missing.** Delivering
        // instantly and synchronously let both peers advance every frame no matter how
        // publishing was keyed — so the starvation could not reproduce. Real packets
        // arrive a frame or two later, and that delay is what turns a sim-driven
        // publish edge into mutual deadlock.
        var stalls = 0
        var time = 0.0
        var inFlightToGuest: [(deliverAt: Int, bytes: [UInt8])] = []
        var inFlightToHost: [(deliverAt: Int, bytes: [UInt8])] = []
        let latencyFrames = 2

        for frame in 0..<600 {
            time += Race.dt
            let before = host.race.tick
            host.advance(to: time)
            guest.advance(to: time)

            for b in hostNet.drainOutbox() {
                inFlightToGuest.append((frame + latencyFrames, b))
            }
            for b in guestNet.drainOutbox() {
                inFlightToHost.append((frame + latencyFrames, b))
            }
            for packet in inFlightToGuest where packet.deliverAt <= frame {
                guestNet.deliverForTesting(packet.bytes, from: "host#aaaa")
            }
            for packet in inFlightToHost where packet.deliverAt <= frame {
                hostNet.deliverForTesting(packet.bytes, from: "guest#bbbb")
            }
            inFlightToGuest.removeAll { $0.deliverAt <= frame }
            inFlightToHost.removeAll { $0.deliverAt <= frame }

            if host.race.tick == before { stalls += 1 }
        }

        // On a perfect link the race must run essentially every frame. Before the fix
        // it stalled roughly half of them, in a rhythm.
        XCTAssertLessThan(stalls, 60, "stalled on \(stalls) of 600 frames with NO packet loss")
        XCTAssertGreaterThan(host.race.tick, 540, "the host barely advanced")
        XCTAssertEqual(host.race.tick, guest.race.tick, "the peers ran to different ticks")
        XCTAssertEqual(host.race.stateHash, guest.race.stateHash, "the peers diverged")
    }

    @MainActor
    private func makeSession(_ start: RaceStart, _ driver: GameSession.LockstepDriver)
        -> GameSession
    {
        let session = GameSession(
            track: TrackLibrary.track(id: "small"), players: start.roster.seats,
            config: RaceConfig(laps: start.laps, countdownTicks: 3 * Race.tickRate),
            seed: start.seed, tuning: start.tuning,
            inputFor: { _, _ in CarInput(throttle: 1) })
        session.lockstep = driver
        return session
    }
}
