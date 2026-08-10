import XCTest

@testable import SkidCore
@testable import SkidKit

/// The host-authoritative model through the REAL session objects — two
/// `NetworkedGame`s and two `GameSession`s, a link with latency and loss between
/// them. Under lockstep, five device sessions went to bugs that lived exactly
/// here, in code no simpler harness executed.
@MainActor
final class HostAuthSessionTests: XCTestCase {
    private var roster = RaceRoster()
    private let hostKey = "host#aaaa"
    private let guestKey = "guest#bbbb"

    override func setUp() {
        super.setUp()
        roster = RaceRoster()
        try? roster.join(hostKey, seats: 1)
        try? roster.join(guestKey, seats: 1)
    }

    private func raceStart() -> RaceStart {
        RaceStart(
            course: .builtin("small"), seed: 5, roster: roster,
            laps: 3, tuning: CarTuning(), carContact: true)
    }

    private func thumb(_ seat: PlayerID, _ tick: Tick) -> CarInput {
        CarInput(steer: sin(Double(tick) / 40 + Double(seat.rawValue)), throttle: 1)
    }

    /// The host's session: local play with remote seats reading the relay —
    /// the same wiring `startNetworkedRace` builds, minus the touch rig.
    private func hostSession(_ start: RaceStart, driver: NetworkedGame) -> GameSession {
        let session = GameSession(
            track: TrackLibrary.track(id: "small"), players: start.roster.seats,
            config: RaceConfig(laps: start.laps, countdownTicks: 60),
            seed: start.seed, tuning: start.tuning,
            inputFor: { [weak self, weak driver] seat, race in
                guard let self, seat == PlayerID(0) else {
                    return driver?.remoteInput(for: seat) ?? .coast
                }
                return self.thumb(seat, race.tick)
            })
        session.isNetworked = true
        session.started = true
        session.generation = driver.generation
        session.onTick = { race in driver.broadcast(race) }
        return session
    }

    private func clientSession(_ start: RaceStart, driver: NetworkedGame) -> GameSession {
        let session = GameSession(
            track: TrackLibrary.track(id: "small"), players: start.roster.seats,
            config: RaceConfig(laps: start.laps, countdownTicks: 60),
            seed: start.seed, tuning: start.tuning,
            inputFor: { [weak self] seat, _ in
                guard let self, seat == PlayerID(1) else { return .coast }
                return self.thumb(seat, 0)
            })
        session.isNetworked = true
        session.started = true
        session.generation = driver.generation
        session.snapshotClient = driver
        return session
    }

    private struct LinkRun {
        var hostHistory: [Tick: Vec2] = [:]
        var rendered: [(tick: Double, position: Vec2)] = []
        var finalHostTick: Tick = 0
        var clientCarFinal: Vec2 = .zero
    }

    private struct LinkedPair {
        let host: GameSession
        let client: GameSession
        let hostNet: NetworkedGame
        let guestNet: NetworkedGame
    }

    /// Drive both real sessions for `frames`, exchanging packets through a link
    /// with two frames of latency and 30% loss each way.
    private func runLinkedSessions(_ pair: LinkedPair, frames: Int) -> LinkRun {
        let host = pair.host
        let client = pair.client
        let hostNet = pair.hostNet
        let guestNet = pair.guestNet
        var rng = SeededRNG(seed: 9)
        var toGuest: [(Int, [UInt8])] = []
        var toHost: [(Int, [UInt8])] = []
        var run = LinkRun()
        var time = 0.0
        for frame in 0..<frames {
            time += Race.dt
            host.advance(to: time)
            run.hostHistory[host.race.tick] = host.race.cars[1].state.position
            client.advance(to: time)
            for bytes in hostNet.drainOutbox() { toGuest.append((frame + 2, bytes)) }
            for bytes in guestNet.drainOutbox() { toHost.append((frame + 2, bytes)) }
            for (at, bytes) in toGuest where at <= frame {
                if rng.next() % 10 >= 3 { guestNet.deliverForTesting(bytes, from: hostKey) }
            }
            for (at, bytes) in toHost where at <= frame {
                if rng.next() % 10 >= 3 { hostNet.deliverForTesting(bytes, from: guestKey) }
            }
            toGuest.removeAll { $0.0 <= frame }
            toHost.removeAll { $0.0 <= frame }
            run.rendered.append((Double(client.race.tick), client.race.cars[1].state.position))
        }
        run.finalHostTick = host.race.tick
        run.clientCarFinal = host.race.cars[1].state.position
        return run
    }

    func testTheHostNeverStallsAndTheClientTracksIt() {
        // The property lockstep could not have: the host runs a tick per frame's
        // worth of wall time, every frame, whatever the link does. 30% loss each
        // way, two frames of latency.
        let start = raceStart()
        let hostNet = NetworkedGame(displayName: hostKey)
        let guestNet = NetworkedGame(displayName: guestKey)
        hostNet.adoptForTesting(start)
        guestNet.adoptForTesting(start)
        XCTAssertTrue(hostNet.isRaceHost)
        XCTAssertFalse(guestNet.isRaceHost)

        let host = hostSession(start, driver: hostNet)
        let client = clientSession(start, driver: guestNet)
        let run = runLinkedSessions(
            LinkedPair(host: host, client: client, hostNet: hostNet, guestNet: guestNet),
            frames: 600)

        // The host cannot stall — one tick per frame, structurally. (Minus one for
        // the first frame, which only anchors the wall clock.)
        XCTAssertEqual(run.finalHostTick, 599)
        // The client's own car MOVED on the host — its thumbs crossed the link and
        // were applied, not coasted. Path length, not displacement: a constant
        // steer at full throttle drives a circle, whose net displacement is small.
        var clientCarPath = 0.0
        var previous = run.hostHistory[1] ?? .zero
        for tick in 2...run.finalHostTick {
            guard let at = run.hostHistory[tick] else { continue }
            clientCarPath += (at - previous).length
            previous = at
        }
        XCTAssertGreaterThan(clientCarPath, 500, "the client's input never reached the host")
        // And what the client shows for tick N is where the host WAS at tick N.
        // The hard bound allows for a loss burst widening the interpolation gap —
        // spanning 30 ticks linearly on a curve cuts more corner than spanning 3.
        // Eight units is under a quarter car length; the MEAN must stay tight.
        var checked = 0
        var totalError = 0.0
        for (tick, position) in run.rendered.suffix(500) {
            guard tick == tick.rounded(), let truth = run.hostHistory[Tick(tick)] else { continue }
            let error = (position - truth).length
            XCTAssertLessThan(error, 8.0, "off the host's line by \(error) at \(tick)")
            totalError += error
            checked += 1
        }
        XCTAssertGreaterThan(checked, 20, "the client never rendered on a whole tick")
        XCTAssertLessThan(totalError / Double(checked), 2.0, "systematically off the line")
        // Continuity: the rendered car never teleports.
        var jumps = 0
        for index in 1..<run.rendered.count
        where (run.rendered[index].position - run.rendered[index - 1].position).length > 30 {
            jumps += 1
        }
        XCTAssertLessThanOrEqual(jumps, 2, "the client's view teleported \(jumps) times")
    }

    func testAClientDoesNotSimulateOrRecord() {
        // The model's one unforgivable bug would be a client treating its own sim
        // as truth. With NO snapshots arriving, a client session must not move a
        // single car — and it never records, because a snapshot stream is not an
        // input recording.
        let start = raceStart()
        let guestNet = NetworkedGame(displayName: guestKey)
        guestNet.adoptForTesting(start)
        let client = clientSession(start, driver: guestNet)
        let positions = client.race.cars.map(\.state.position)
        var time = 0.0
        for _ in 0..<120 {
            time += Race.dt
            client.advance(to: time)
        }
        XCTAssertEqual(client.race.tick, 0, "the client simulated on its own")
        XCTAssertEqual(client.race.cars.map(\.state.position), positions)
        XCTAssertTrue(client.recording.inputs.isEmpty, "a client recorded snapshots as inputs")
        // But its thumbs still went out — input must flow even before video does.
        XCTAssertFalse(guestNet.drainOutbox().isEmpty, "the client never published input")
    }

    func testTheHostBroadcastsOnTheCadenceNotEveryTick() {
        // The packet-rate lesson, pinned at the session level: a 60 Hz send rate
        // is what choked MC. Twenty snapshots a second, not sixty.
        let start = raceStart()
        let hostNet = NetworkedGame(displayName: hostKey)
        hostNet.adoptForTesting(start)
        let host = hostSession(start, driver: hostNet)
        var time = 0.0
        for _ in 0..<121 {
            time += Race.dt
            host.advance(to: time)
        }
        let snapshots = hostNet.drainOutbox().filter { $0.first == 3 }
        // Against the ticks that actually ran (the first advance only anchors the
        // wall clock), not a hand-count that drifts with FP accumulation.
        XCTAssertEqual(snapshots.count, host.race.tick / 3, "one snapshot per three ticks")
        XCTAssertGreaterThan(host.race.tick, 110, "the host barely ran")
    }

    func testLocalPlayIsUntouchedByTheNetworkedSeam() {
        // The regression that would matter most, kept from the lockstep suite:
        // adding networking must not change a couch race by one tick.
        let players = [PlayerID(0), PlayerID(1)]
        let session = GameSession(
            track: TrackLibrary.testRing(), players: players, config: RaceConfig(),
            seed: 4, inputFor: { [weak self] seat, race in self?.thumb(seat, race.tick) ?? .coast })
        session.started = true
        var time = 0.0
        for _ in 0..<120 {
            time += Race.dt
            session.advance(to: time)
        }
        XCTAssertGreaterThan(session.race.tick, 100)

        var direct = Race(track: TrackLibrary.testRing(), players: players, seed: 4)
        while direct.tick < session.race.tick {
            var inputs: [PlayerID: CarInput] = [:]
            for seat in players { inputs[seat] = thumb(seat, direct.tick) }
            direct.advance(inputs: inputs)
        }
        XCTAssertEqual(direct.stateHash, session.race.stateHash, "the local path changed")
    }

    func testARematchLeavesTheOldSessionInertAndTheNewOneDriving() {
        // **Reported from device: after a rematch, the client's car did not move.**
        // A rematch builds a new session while the old one may still be on screen,
        // and both hold the same driver — so the stale session kept pulling the
        // driver's snapshots for a race that no longer existed. Measured before the
        // fix: the stale session sat frozen at the previous race's last tick (191)
        // while the new one never left 0, and it was the stale one on screen.
        let hostNet = NetworkedGame(displayName: "host#aaaa")
        let guestNet = NetworkedGame(displayName: "guest#bbbb")
        hostNet.captureSendsForTesting()
        guestNet.captureSendsForTesting()
        hostNet.host(seats: 1)
        guestNet.join(seats: 1)
        guestNet.transport(peerJoined: "host#aaaa")
        hostNet.transport(peerJoined: "guest#bbbb")
        guestNet.askToJoin("host#aaaa")
        settle(hostNet, guestNet)
        hostNet.approve("guest#bbbb")
        settle(hostNet, guestNet)

        var host: GameSession?
        var client: GameSession?
        hostNet.onStart { start in host = self.hostSession(start, driver: hostNet) }
        guestNet.onStart { start in client = self.clientSession(start, driver: guestNet) }

        hostNet.startRace(course: .builtin("small"), seed: 1, laps: 3)
        settle(hostNet, guestNet)
        var time = 0.0
        for _ in 0..<200 {
            time += Race.dt
            host?.advance(to: time)
            client?.advance(to: time)
            settle(hostNet, guestNet, rounds: 1)
        }
        let firstRaceTick = client?.race.tick ?? -1
        XCTAssertGreaterThan(firstRaceTick, 150, "the first race did not run")

        // Rematch, keeping the old session alive as the app does for a frame or two.
        let stale = client
        hostNet.returnToLobby()
        guestNet.returnToLobby()
        hostNet.rematch(seed: 2)
        settle(hostNet, guestNet)
        XCTAssertFalse(stale === client, "the session was not rebuilt")

        for _ in 0..<200 {
            time += Race.dt
            host?.advance(to: time)
            stale?.advance(to: time)  // still on screen
            client?.advance(to: time)
            settle(hostNet, guestNet, rounds: 1)
        }

        // The stale session must be INERT: it neither advances nor eats snapshots.
        XCTAssertEqual(stale?.race.tick, firstRaceTick, "the stale session kept running")
        // And the new one must actually be driving.
        XCTAssertGreaterThan(client?.race.tick ?? -1, 150, "the new race never moved")
        XCTAssertGreaterThan(host?.race.tick ?? -1, 150)
    }

    private func settle(_ a: NetworkedGame, _ b: NetworkedGame, rounds: Int = 6) {
        for _ in 0..<rounds {
            let fromA = a.drainOutbox()
            let fromB = b.drainOutbox()
            if fromA.isEmpty, fromB.isEmpty { return }
            for bytes in fromA { b.deliverForTesting(bytes, from: a.me) }
            for bytes in fromB { a.deliverForTesting(bytes, from: b.me) }
        }
    }
}
