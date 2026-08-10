import XCTest

@testable import SkidCore

/// Host-authoritative sync under the conditions that actually exist: latency on
/// every packet and loss on many. The lockstep spike's costliest lesson was a
/// harness with instant delivery — a network that cannot fail like a network —
/// so every test here ships packets through a delayed, lossy link.
final class NetworkedSyncTests: XCTestCase {
    private var roster = RaceRoster()

    override func setUp() {
        super.setUp()
        roster = RaceRoster()
        try? roster.join("host#aaaa", seats: 1)
        try? roster.join("guest#bbbb", seats: 1)
    }

    private func thumb(_ seat: PlayerID, _ tick: Tick) -> CarInput {
        CarInput(steer: sin(Double(tick) / 40 + Double(seat.rawValue)), throttle: 1)
    }

    // MARK: - The host's half

    func testTheHostHoldsTheLatestInputAndNeverRegresses() {
        var relay = HostRelay(roster: roster, me: "host#aaaa")
        var client = ClientView(roster: roster, me: "guest#bbbb")
        let seat = PlayerID(1)

        // Two packets, delivered OUT OF ORDER — the unreliable channel's habit.
        var packets: [[UInt8]] = []
        for tick in 0..<4 {
            if let bytes = client.publish([seat: CarInput(steer: Double(tick) / 10, throttle: 1)]) {
                packets.append(bytes)
            }
        }
        XCTAssertEqual(packets.count, 2, "every second frame sends")
        relay.receive(packets[1], from: "guest#bbbb")
        let newest = relay.input(for: seat).steer
        relay.receive(packets[0], from: "guest#bbbb")
        XCTAssertEqual(
            relay.input(for: seat).steer, newest,
            "a stale packet yanked the input backwards")
        // And it holds between packets — the move lockstep forbade, safe here.
        XCTAssertEqual(relay.input(for: seat).throttle, 1)
    }

    func testOnlySeatedPeersAndOnlyInputCount() {
        var relay = HostRelay(roster: roster, me: "host#aaaa")
        var client = ClientView(roster: roster, me: "guest#bbbb")
        guard let bytes = clientInput(&client, steer: 0.5) else { return XCTFail("no packet") }
        XCTAssertFalse(relay.receive(bytes, from: "gatecrasher"), "an outsider was believed")
        XCTAssertFalse(relay.receive(bytes, from: "host#aaaa"), "our own echo was believed")
        XCTAssertFalse(relay.receive([2, 1, 2, 3], from: "guest#bbbb"), "a retired hash tag")
        XCTAssertFalse(relay.receive([], from: "guest#bbbb"))
        XCTAssertTrue(relay.receive(bytes, from: "guest#bbbb"))
        // Fuzz — this parses network data.
        var rng = SeededRNG(seed: 5)
        for length in 0..<60 {
            let junk = (0..<length).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            _ = relay.receive(junk, from: "guest#bbbb")
        }
    }

    func testADepartedPeersCarsCoast() {
        var relay = HostRelay(roster: roster, me: "host#aaaa")
        var client = ClientView(roster: roster, me: "guest#bbbb")
        guard let bytes = clientInput(&client, steer: 1) else { return XCTFail("no packet") }
        relay.receive(bytes, from: "guest#bbbb")
        XCTAssertEqual(relay.input(for: PlayerID(1)).throttle, 1)
        relay.peerLeft("guest#bbbb")
        XCTAssertEqual(
            relay.input(for: PlayerID(1)), .coast,
            "a departed player's held throttle would grind a wall forever")
    }

    // MARK: - The client's half

    func testSnapshotsFromAnyoneButTheHostAreRefused() {
        var view = ClientView(roster: roster, me: "guest#bbbb")
        let race = Race(track: TrackLibrary.testRing(), players: roster.seats, seed: 3)
        let message = HostRelay.snapshotMessage(for: race)
        XCTAssertFalse(view.receive(message, from: "impostor#cccc"), "one word is the race")
        XCTAssertTrue(view.receive(message, from: "host#aaaa"))
    }

    func testTheViewNeverMovesBackwards() {
        // Reordered snapshots must supersede, not rewind: a car that visibly
        // jumps back mid-corner is the artefact this whole layer exists to avoid.
        var view = ClientView(roster: roster, me: "guest#bbbb")
        var race = Race(track: TrackLibrary.testRing(), players: roster.seats, seed: 3)
        var messages: [(Tick, [UInt8])] = []
        for _ in 0..<10 {
            for _ in 0..<3 { race.advance(inputs: [PlayerID(0): thumb(PlayerID(0), race.tick)]) }
            messages.append((race.tick, HostRelay.snapshotMessage(for: race)))
        }
        // Deliver with the middle pair swapped. The stale one must be REFUSED, not
        // buffered out of order — the render smoothing can absorb one swap, so the
        // buffer property is asserted directly rather than through the smoothing.
        messages.swapAt(4, 5)
        for (index, (tick, bytes)) in messages.enumerated() {
            let accepted = view.receive(bytes, from: "host#aaaa")
            XCTAssertEqual(
                accepted, index != 5,
                "snapshot for tick \(tick) — stale must be refused, fresh accepted")
            XCTAssertEqual(view.newestTick, messages.prefix(index + 1).map(\.0).max())
        }

        var lastTick = -1.0
        for _ in 0..<120 {
            guard let frame = view.view(advancedBy: Race.dt) else { continue }
            XCTAssertGreaterThanOrEqual(
                Double(frame.tick) + 0.001, lastTick, "the view rewound")
            lastTick = Double(frame.tick)
        }
        XCTAssertGreaterThan(lastTick, 0, "the view never rendered at all")
    }

    func testStarvationIsReportedNotGuessedAt() {
        var view = ClientView(roster: roster, me: "guest#bbbb")
        let race = Race(track: TrackLibrary.testRing(), players: roster.seats, seed: 3)
        view.receive(HostRelay.snapshotMessage(for: race), from: "host#aaaa")
        _ = view.view(advancedBy: 0.5)
        XCTAssertFalse(view.isStarved)
        _ = view.view(advancedBy: 0.6)
        XCTAssertTrue(view.isStarved, "a quiet host must be reportable")
        view.receive(HostRelay.snapshotMessage(for: race), from: "host#aaaa")
        XCTAssertFalse(view.receive([], from: "host#aaaa"))
    }

    // MARK: - End to end, through a bad link

    func testAClientRendersTheHostsRaceThroughALossyLatentLink() {
        // The money test. The host simulates; snapshots and inputs cross a link
        // with two frames of latency and 30% loss each way; the client's rendered
        // car must track the host's actual past positions and move continuously.
        let run = simulateLossyRace(frames: 600, lossOutOfTen: 3, latencyFrames: 2)
        XCTAssertGreaterThan(run.rendered.count, 500, "the client barely rendered")

        // Accuracy: what the client shows for tick N is where the host WAS at N.
        // The bound is the geometry's, not a hope: linear blending of 20 Hz samples
        // cuts corners by up to a couple of units at full speed on a curve. Four
        // units is an eighth of a car length; the mean must stay well under one.
        var checked = 0
        var totalError = 0.0
        for (tick, position) in run.rendered {
            let nearest = Tick(tick.rounded())
            guard tick == tick.rounded(), let truth = run.hostHistory[nearest] else { continue }
            let error = (position - truth).length
            XCTAssertLessThan(error, 4.0, "off the host's line by \(error) at \(nearest)")
            totalError += error
            checked += 1
        }
        XCTAssertGreaterThan(checked, 20, "no rendered frame landed on a whole tick")
        XCTAssertLessThan(totalError / Double(checked), 1.5, "systematically off the line")

        // Continuity: no rendered jump may exceed what a car can cover, with slack
        // for the one legal snap after deep starvation.
        var jumps = 0
        for index in 1..<run.rendered.count {
            let step = (run.rendered[index].position - run.rendered[index - 1].position).length
            if step > 30 { jumps += 1 }
        }
        XCTAssertLessThanOrEqual(jumps, 2, "the view teleported \(jumps) times")
        // And the host never stalled — it cannot, structurally.
        XCTAssertEqual(run.finalHostTick, 600)
    }

    private struct LossyRun {
        var hostHistory: [Tick: Vec2] = [:]
        var rendered: [(tick: Double, position: Vec2)] = []
        var finalHostTick: Tick = 0
    }

    private func simulateLossyRace(frames: Int, lossOutOfTen: UInt64, latencyFrames: Int)
        -> LossyRun
    {
        var relay = HostRelay(roster: roster, me: "host#aaaa")
        var view = ClientView(roster: roster, me: "guest#bbbb")
        var race = Race(track: TrackLibrary.testRing(), players: roster.seats, seed: 3)
        var rng = SeededRNG(seed: 77)
        var toClient: [(Int, [UInt8])] = []
        var toHost: [(Int, [UInt8])] = []
        var run = LossyRun()

        for frame in 0..<frames {
            let inputs: [PlayerID: CarInput] = [
                PlayerID(0): thumb(PlayerID(0), race.tick),
                PlayerID(1): relay.input(for: PlayerID(1)),
            ]
            race.advance(inputs: inputs)
            run.hostHistory[race.tick] = race.cars[0].state.position
            if relay.shouldBroadcast(after: race.tick) {
                toClient.append((frame + latencyFrames, HostRelay.snapshotMessage(for: race)))
            }
            if let bytes = view.publish([PlayerID(1): thumb(PlayerID(1), Tick(frame))]) {
                toHost.append((frame + latencyFrames, bytes))
            }
            for (at, bytes) in toClient where at <= frame {
                if rng.next() % 10 >= lossOutOfTen { view.receive(bytes, from: "host#aaaa") }
            }
            for (at, bytes) in toHost where at <= frame {
                if rng.next() % 10 >= lossOutOfTen { relay.receive(bytes, from: "guest#bbbb") }
            }
            toClient.removeAll { $0.0 <= frame }
            toHost.removeAll { $0.0 <= frame }
            if let shown = view.view(advancedBy: Race.dt) {
                run.rendered.append((Double(shown.tick), shown.cars[0].position))
            }
        }
        run.finalHostTick = race.tick
        return run
    }

    private func clientInput(_ view: inout ClientView, steer: Double) -> [UInt8]? {
        for _ in 0..<4 {
            if let bytes = view.publish([PlayerID(1): CarInput(steer: steer, throttle: 1)]) {
                return bytes
            }
        }
        return nil
    }

    func testBurstyDeliveryCostsLatencyNotRhythm() {
        // **The 2 Hz stutter, reported from device THREE times — and it survived
        // the model change, because it was never the model.** The transport
        // delivers in ~500 ms bursts (the peer-to-peer radio duty-cycles), so a
        // fixed 75 ms buffer starved between bursts and the client pulsed at the
        // burst rate. The lag must adapt to the observed arrival rhythm: a bursty
        // link costs latency, never rhythm.
        var relay = HostRelay(roster: roster, me: "host#aaaa")
        var view = ClientView(roster: roster, me: "guest#bbbb")
        var race = Race(track: TrackLibrary.testRing(), players: roster.seats, seed: 3)
        _ = relay

        var pending: [[UInt8]] = []
        var pauses = 0
        var frames = 0
        var lastRendered = -1.0
        for frame in 0..<900 {
            race.advance(inputs: [PlayerID(0): thumb(PlayerID(0), race.tick)])
            if race.tick % 3 == 0 {
                pending.append(HostRelay.snapshotMessage(for: race))
            }
            // The burst: nothing for half a second, then everything at once.
            if frame % 30 == 29 {
                for bytes in pending { view.receive(bytes, from: "host#aaaa") }
                pending.removeAll()
            }
            guard let shown = view.view(advancedBy: Race.dt) else { continue }
            // Skip the warm-up: the first burst is what teaches the lag its size.
            if frame > 120 {
                frames += 1
                if Double(shown.tick) <= lastRendered { pauses += 1 }
            }
            lastRendered = Double(shown.tick)
        }

        XCTAssertGreaterThan(frames, 700, "the view barely rendered")
        // A fixed 75 ms lag pauses on roughly half of all frames here. Adapted,
        // the view must advance on nearly every frame — the burst becomes delay.
        XCTAssertLessThan(
            pauses, frames / 10,
            "the view paused on \(pauses) of \(frames) frames — the burst became rhythm")
        // And the price is visible and bounded: the lag grew to cover the burst.
        XCTAssertGreaterThan(view.lagTicks, 25, "the lag never adapted to the burst")
        XCTAssertLessThanOrEqual(view.lagTicks, 45, "the lag must stay bounded")
    }
}
