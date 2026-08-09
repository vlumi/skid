import Combine
import XCTest

@testable import SkidCore
@testable import SkidKit

/// `GameSession`'s two tick-driving modes. The local one must be untouched — it is
/// what ships today — and the networked one must never step a tick the clock has
/// not released.
@MainActor
final class LockstepSessionTests: XCTestCase {
    private func makeSession(
        players: [PlayerID], inputFor: @escaping (PlayerID, Race) -> CarInput
    ) -> GameSession {
        let session = GameSession(
            track: TrackLibrary.testRing(), players: players, config: RaceConfig(),
            seed: 4, inputFor: inputFor)
        session.started = true
        return session
    }

    func testANetworkedRaceDoesNotWaitOnALocalReadyTap() {
        // **The deadlock, reported from device: stuck at "3" on both phones.**
        // `started` is a per-device gate, and a device that has not started
        // publishes no input — so no peer's clock can release a tick, so nobody's
        // countdown ever moves. The lobby's "Start race" is the shared gate, and it
        // is the only one there can be.
        let seats = [PlayerID(0)]
        let session = GameSession(
            track: TrackLibrary.testRing(), players: seats, config: RaceConfig(),
            seed: 4, inputFor: { _, _ in CarInput(throttle: 1) })
        XCTAssertFalse(session.started, "a local race still waits for its tap")

        session.lockstep = LoopbackDriver(seats: seats)
        XCTAssertTrue(session.started, "a networked race waited for a tap nobody can give")

        // And it really advances, rather than merely claiming to be started.
        var time = 0.0
        for _ in 0..<60 {
            time += Race.dt
            session.advance(to: time)
        }
        XCTAssertGreaterThan(session.race.tick, 30, "the countdown never moved")
    }

    func testDrivingTheRaceDoesNotPublishPerTick() {
        // **The freeze, reported from device three times.** `RaceScreen` observes
        // `NetworkedGame`, and its per-tick diagnostics were `@Published` — so every
        // simulated tick mutated observable state from inside the render pass, which
        // invalidated the view, which re-entered the tick loop. The lobby reached
        // `.racing` and the app locked up.
        //
        // `GameSession` already documents this trap and publishes nothing per frame;
        // the networking reintroduced it. So: count the change notifications a
        // frame's worth of ticks produces. It must be zero.
        let net = NetworkedGame(displayName: "solo#aaaa")
        net.host(seats: 1)
        var published = 0
        let token = net.objectWillChange.sink { _ in published += 1 }
        defer { token.cancel() }

        net.startRace(course: .builtin("small"), seed: 3, laps: 3)
        published = 0  // the start itself legitimately publishes (phase, roster)

        for tick in 0..<120 {
            net.publish([PlayerID(0): CarInput(throttle: 1)], at: Tick(tick))
            _ = net.nextTick()
            net.report(hash: UInt64(tick), at: Tick(tick))
        }
        XCTAssertEqual(published, 0, "driving the race published \(published) times")
    }

    func testALocalRaceStillWaitsForItsReadyTap() {
        // The other half, and a real regression risk: opening the gate for every
        // race would skip the ready screen a couch game depends on — everyone gets
        // their thumbs in place before the lights.
        let session = GameSession(
            track: TrackLibrary.testRing(), players: [PlayerID(0)], config: RaceConfig(),
            seed: 4, inputFor: { _, _ in CarInput(throttle: 1) })
        XCTAssertFalse(session.started)
        var time = 0.0
        for _ in 0..<60 {
            time += Race.dt
            session.advance(to: time)
        }
        XCTAssertEqual(session.race.tick, 0, "a local race started without being tapped")
    }

    func testLocalPlayIsUnaffectedByTheLockstepSeam() {
        // The regression that would matter most: adding networking must not change
        // a couch race by one tick.
        let players = [PlayerID(0), PlayerID(1)]
        let script: (PlayerID, Race) -> CarInput = { seat, race in
            CarInput(steer: sin(Double(race.tick) / 30 + Double(seat.rawValue)), throttle: 1)
        }
        let session = makeSession(players: players, inputFor: script)
        var time = 0.0
        for _ in 0..<120 {
            time += Race.dt
            session.advance(to: time)
        }
        XCTAssertGreaterThan(session.race.tick, 100, "the local race barely advanced")

        // The same script through the sim directly.
        var direct = Race(track: TrackLibrary.testRing(), players: players, seed: 4)
        while direct.tick < session.race.tick {
            var inputs: [PlayerID: CarInput] = [:]
            for seat in players { inputs[seat] = script(seat, direct) }
            direct.advance(inputs: inputs)
        }
        XCTAssertEqual(direct.stateHash, session.race.stateHash, "the local path changed")
    }

    /// A driver that withholds ticks until told to release them — the "peer went
    /// quiet, then came back" case.
    private final class GateDriver: GameSession.LockstepDriver {
        var mySeats: [PlayerID]
        var delayTicks: Int { 0 }
        var open = false
        var published = 0
        private var queue: [[PlayerID: CarInput]] = []
        init(seats: [PlayerID]) { mySeats = seats }
        func publish(_ inputs: [PlayerID: CarInput], at tick: Tick) {
            published += 1
            queue.append(inputs)
        }
        func nextTick() -> [PlayerID: CarInput]? {
            guard open, !queue.isEmpty else { return nil }
            return queue.removeFirst()
        }
        func report(hash: UInt64, at tick: Tick) {}
    }

    func testAStalledNetworkFreezesTheSimWithoutLosingTheDebt() {
        // Nothing may advance, and — the subtle half — the owed ticks must NOT be
        // discarded. Draining the accumulator on a stall would silently skip part
        // of the race once inputs resumed.
        let session = makeSession(players: [PlayerID(0)], inputFor: { _, _ in .coast })
        let driver = GateDriver(seats: [PlayerID(0)])
        session.lockstep = driver
        var time = 0.0
        for _ in 0..<60 {
            time += Race.dt
            session.advance(to: time)
        }
        XCTAssertEqual(session.race.tick, 0, "the sim ran without the clock releasing a tick")
        XCTAssertGreaterThan(driver.published, 0, "our own input was never published")
        XCTAssertEqual(session.recording.inputs.count, 0, "a stalled tick was recorded")

        // **The owed ticks must still be owed.** Draining the accumulator on a
        // stall loses them silently: the race would resume having skipped a
        // second of itself, and every peer that DID receive those inputs would be
        // a second ahead. Asserting only "it did not advance" misses this
        // entirely — one frame's worth would then catch up, not sixty.
        driver.open = true
        time += Race.dt
        session.advance(to: time)
        XCTAssertGreaterThan(
            session.race.tick, 10,
            "the stalled ticks were discarded instead of being owed")
    }

    /// A driver that echoes our own input straight back — a one-device "network".
    fileprivate final class LoopbackDriver: GameSession.LockstepDriver {
        var mySeats: [PlayerID]
        var delayTicks: Int { 0 }
        private var queue: [[PlayerID: CarInput]] = []
        var reported: [UInt64] = []
        init(seats: [PlayerID]) { mySeats = seats }
        func publish(_ inputs: [PlayerID: CarInput], at tick: Tick) { queue.append(inputs) }
        func nextTick() -> [PlayerID: CarInput]? { queue.isEmpty ? nil : queue.removeFirst() }
        func report(hash: UInt64, at tick: Tick) { reported.append(hash) }
    }

    func testANetworkedSessionStepsOnlyWhatTheClockReleases() {
        let seats = [PlayerID(0)]
        let session = makeSession(players: seats, inputFor: { _, _ in CarInput(throttle: 1) })
        let driver = LoopbackDriver(seats: seats)
        session.lockstep = driver
        var time = 0.0
        for _ in 0..<90 {
            time += Race.dt
            session.advance(to: time)
        }
        XCTAssertGreaterThan(session.race.tick, 60, "loopback never let the race run")
        // Every tick reported a hash, so a peer could have compared them.
        XCTAssertEqual(driver.reported.count, session.race.tick)
        XCTAssertEqual(Set(driver.reported).count, driver.reported.count, "hashes repeated")
    }

    /// A driver that withholds ticks, then releases — and records which ticks it was
    /// asked to publish for.
    private final class RecordingDriver: GameSession.LockstepDriver {
        var mySeats: [PlayerID] { [PlayerID(0)] }
        let delayTicks: Int
        var open = false
        var published: [Tick] = []
        private var queue: [(Tick, [PlayerID: CarInput])] = []
        init(delayTicks: Int) { self.delayTicks = delayTicks }
        func publish(_ inputs: [PlayerID: CarInput], at tick: Tick) {
            published.append(tick)
            queue.append((tick, inputs))
        }
        func nextTick() -> [PlayerID: CarInput]? {
            guard open, !queue.isEmpty else { return nil }
            return queue.removeFirst().1
        }
        func report(hash: UInt64, at tick: Tick) {}
    }

    func testTheTickAnInputIsPublishedForComesFromTheSim() {
        // **The desync, reported from device as a ~200-unit positional offset.**
        //
        // The publish tick was a LOCAL counter, incremented once per attempted tick
        // — and this loop runs every frame, including the ones that stall. So a
        // device that waited published 50 inputs for 31 simulated ticks (measured),
        // and each peer drifted by however much IT stalled. The same thumb press was
        // then labelled tick 40 on one device and tick 31 on the other, and the cars
        // genuinely diverged. The hash comparison was right; I misread it.
        //
        // Deriving the tick from `race.tick` makes it a value both peers agree on,
        // because it comes from the shared simulation rather than local wall time.
        let driver = RecordingDriver(delayTicks: 2)
        let session = GameSession(
            track: TrackLibrary.testRing(), players: [PlayerID(0)], config: RaceConfig(),
            seed: 4, inputFor: { _, _ in CarInput(throttle: 1) })
        session.lockstep = driver

        var time = 0.0
        for frame in 0..<40 {
            if frame == 20 { driver.open = true }  // stalled for the first 20 frames
            time += Race.dt
            session.advance(to: time)
        }

        // One publish per SIMULATED tick, never per attempt. Before the fix this was
        // 50 for 31; the numbers now match by construction.
        XCTAssertEqual(
            driver.published.count, session.race.tick,
            "published \(driver.published.count) inputs for \(session.race.tick) ticks")
        XCTAssertGreaterThan(session.race.tick, 15, "the race never got going")
        // Strictly increasing, no repeats — a repeat would be silently ignored by
        // the clock's first-value-wins rule and lose that input.
        XCTAssertEqual(driver.published, driver.published.sorted())
        XCTAssertEqual(Set(driver.published).count, driver.published.count, "a tick repeated")
        // And each one is the sim's tick plus the buffer, which is what the peer
        // computes for the same press.
        XCTAssertEqual(driver.published.first, driver.delayTicks)
        XCTAssertEqual(
            driver.published.last, session.race.tick - 1 + driver.delayTicks,
            "the newest publish must be the sim's next tick plus the buffer")
    }
}
