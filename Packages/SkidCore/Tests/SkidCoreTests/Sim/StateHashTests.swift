import XCTest

@testable import SkidCore

/// The state hash, and what it buys: a divergence reported at the tick it
/// happened rather than 1800 ticks later. Everything lockstep networking will do
/// across two devices is done here in one process first — if it fails here,
/// nothing over a network can work.
final class StateHashTests: XCTestCase {
    /// A wiggly script exercising steer, gas, brake and coast — the same shape
    /// `DeterminismTests` uses, kept independent so tuning one cannot silently
    /// weaken the other.
    private func scriptedInput(player: PlayerID, tick: Tick) -> CarInput {
        let phase = Double(tick) / 60.0
        let steer = sin(phase * 1.7 + Double(player.rawValue))
        let throttle: Double = tick % 240 < 160 ? 1 : (tick % 240 < 200 ? 0 : -1)
        return CarInput(steer: steer, throttle: throttle)
    }

    private func record(seed: UInt64, ticks: Int, players: Int = 4) -> RaceRecording {
        let ids = (0..<players).map { PlayerID($0) }
        var recording = RaceRecording(seed: seed, players: ids)
        for tick in 0..<ticks {
            var inputs: [PlayerID: CarInput] = [:]
            for id in ids { inputs[id] = scriptedInput(player: id, tick: Tick(tick)) }
            recording.append(inputs)
        }
        return recording
    }

    private func hashes(seed: UInt64, ticks: Int, players: Int = 4) -> [UInt64] {
        record(seed: seed, ticks: ticks, players: players)
            .replayHashes(on: TrackLibrary.testRing())
    }

    // MARK: - What the hash is for

    /// The point of the whole file: two runs that disagree say **when**.
    func testTheFirstDivergingTickIsIdentified() {
        let clean = hashes(seed: 42, ticks: 120)
        // A race nudged at a known tick — one car's throttle cut at tick 50.
        var recording = record(seed: 42, ticks: 120)
        recording.inputs[50][PlayerID(1)] = CarInput(steer: 0, throttle: 0)
        let nudged = recording.replayHashes(on: TrackLibrary.testRing())

        let firstDivergence = Array(zip(clean, nudged)).firstIndex { $0 != $1 }
        XCTAssertEqual(firstDivergence, 50, "the hash must pin divergence to the tick it happened")
        // And the prefix really is identical, so the report is not luck.
        XCTAssertEqual(Array(clean.prefix(50)), Array(nudged.prefix(50)))
    }

    func testIdenticalRunsHashIdenticallyEveryTick() {
        XCTAssertEqual(hashes(seed: 42, ticks: 600), hashes(seed: 42, ticks: 600))
    }

    func testAReplayedRecordingMatchesTheLiveRunTickForTick() {
        // Lockstep, single process: the recording IS the wire protocol with the
        // network removed, so its hash sequence must match a live run's.
        let ids = (0..<4).map { PlayerID($0) }
        var race = Race(track: TrackLibrary.testRing(), players: ids, seed: 7)
        var recording = RaceRecording(seed: 7, players: ids)
        var live: [UInt64] = []
        for _ in 0..<600 {
            var inputs: [PlayerID: CarInput] = [:]
            for id in ids { inputs[id] = scriptedInput(player: id, tick: race.tick) }
            recording.append(inputs)
            race.advance(inputs: inputs)
            live.append(race.stateHash)
        }
        XCTAssertEqual(live, recording.replayHashes(on: TrackLibrary.testRing()))
        XCTAssertEqual(recording.replay(on: TrackLibrary.testRing()).stateHash, live.last)
    }

    // MARK: - The hash notices things

    func testDifferentSeedsDiverge() {
        // Different grid shuffle → different states from tick one. Seeds picked
        // because they permute FOUR cars differently: with only 24 permutations,
        // plenty of seed pairs collide (1 and 2 do) and would make this vacuous.
        let ids = (0..<4).map(PlayerID.init)
        let one = Race(track: TrackLibrary.testRing(), players: ids, seed: 1)
        let three = Race(track: TrackLibrary.testRing(), players: ids, seed: 3)
        XCTAssertNotEqual(
            one.cars.map(\.state.position), three.cars.map(\.state.position),
            "seeds chosen for this test no longer shuffle differently")
        XCTAssertNotEqual(hashes(seed: 1, ticks: 60), hashes(seed: 3, ticks: 60))
    }

    func testTheHashChangesEveryTickWhileCarsAreMoving() {
        // A hash that got stuck would make every comparison above vacuous.
        let sequence = hashes(seed: 42, ticks: 300)
        XCTAssertEqual(Set(sequence).count, sequence.count, "hash repeated while cars moved")
    }

    /// Each field the sim carries, changed one at a time. A hand-picked subset
    /// would pass most of these and leave real divergence invisible —
    /// `steerActuator` especially, which reads like a rendering detail and is
    /// carried state.
    func testEveryPieceOfCarStateIsCovered() {
        let base = Race(track: TrackLibrary.testRing(), players: [PlayerID(0)], seed: 5)
        let mutations: [(String, (inout Car) -> Void)] = [
            ("position", { $0.state.position.x += 1 }),
            ("velocity", { $0.state.velocity.y += 1 }),
            ("heading", { $0.state.heading += 0.1 }),
            ("height", { $0.state.height += 1 }),
            ("airborneTicks", { $0.state.airborneTicks += 1 }),
            ("verticalSpeed", { $0.state.verticalSpeed += 1 }),
            ("steerActuator", { $0.state.steerActuator += 0.1 }),
            ("nextGate", { $0.progress.nextGate += 1 }),
            ("lap", { $0.progress.lap += 1 }),
            ("lapStartTick", { $0.progress.lapStartTick += 1 }),
            ("lapTimes", { $0.progress.lapTimes.append(123) }),
            ("finishedAt", { $0.progress.finishedAt = 99 }),
        ]
        for (name, mutate) in mutations {
            var race = base
            mutate(&race.cars[0])
            XCTAssertNotEqual(race.stateHash, base.stateHash, "\(name) is not hashed")
        }
    }

    func testTheTickItselfIsHashed() {
        // Two races in the same state at different ticks are not the same state:
        // a peer a tick behind must not look synchronized.
        let players = [PlayerID(0)]
        var race = Race(track: TrackLibrary.testRing(), players: players, seed: 5)
        let atZero = race.stateHash
        race.advance(inputs: [:])  // a stationary car with no input: nothing physical moves
        let fresh = Race(track: TrackLibrary.testRing(), players: players, seed: 5)
        XCTAssertEqual(race.cars[0].state.position, fresh.cars[0].state.position)
        XCTAssertEqual(race.cars[0].state.velocity, fresh.cars[0].state.velocity)
        XCTAssertNotEqual(race.stateHash, atZero, "the tick must be part of the hash")
    }

    func testCarOrderMatters() {
        // Two cars with swapped states is a different world, and a hash that
        // summed or xored per-car digests would call it the same one.
        //
        // The cars must be given DIFFERENT state first. On the grid they differ
        // only in position, and swapping two otherwise-identical cars really is a
        // no-op — an earlier version of this test swapped them as-placed and stayed
        // green even with car identity removed from the hash entirely.
        var race = Race(
            track: TrackLibrary.testRing(), players: [PlayerID(0), PlayerID(1)], seed: 5)
        race.cars[0].progress.lap = 2
        race.cars[1].progress.nextGate = 3
        let before = race.stateHash
        race.cars.swapAt(0, 1)
        XCTAssertNotEqual(race.stateHash, before, "swapping two cars must change the hash")
    }

    func testCarIdentityIsHashed() {
        // Seat identity, independent of state. `Car.id` is a `let`, so it cannot
        // drift mid-race and hashing it is defensive rather than load-bearing —
        // but under networking the seats come off the wire, and two peers that
        // disagree about WHICH seat is which must not report agreement.
        let track = TrackLibrary.testRing()
        let asZero = Race(track: track, players: [PlayerID(0)], seed: 5)
        let asSeven = Race(track: track, players: [PlayerID(7)], seed: 5)
        // Same single car, same slot, same everything but the seat number.
        XCTAssertEqual(asZero.cars[0].state, asSeven.cars[0].state)
        XCTAssertNotEqual(asSeven.stateHash, asZero.stateHash, "car identity is not hashed")
    }

    func testFieldsAreNotInterchangeable() {
        // Moving a value from one field to another must change the hash. A hash
        // that fed all its Doubles into one accumulator without position would
        // report these two states as identical.
        var moved = Race(track: TrackLibrary.testRing(), players: [PlayerID(0)], seed: 5)
        var swapped = moved
        moved.cars[0].state.velocity = Vec2(3, 0)
        swapped.cars[0].state.velocity = Vec2(0, 3)
        XCTAssertNotEqual(moved.stateHash, swapped.stateHash)
    }

    // MARK: - The hash itself

    func testNegativeZeroHashesAsZero() {
        // IEEE-754 has two zeros with different bit patterns. A car that stopped
        // from the left would otherwise hash differently from one that stopped
        // from the right — a false divergence, the worst kind.
        var negative = Race(track: TrackLibrary.testRing(), players: [PlayerID(0)], seed: 5)
        var positive = negative
        negative.cars[0].state.velocity = Vec2(-0.0, -0.0)
        positive.cars[0].state.velocity = Vec2(0.0, 0.0)
        XCTAssertEqual(negative.cars[0].state.velocity, positive.cars[0].state.velocity)
        XCTAssertEqual(negative.stateHash, positive.stateHash)
    }

    func testTheHashSeparatesNeighboringBitPatterns() {
        // The divergence this exists to catch is one ULP, not a visible jump.
        var nudged = Race(track: TrackLibrary.testRing(), players: [PlayerID(0)], seed: 5)
        let base = nudged.stateHash
        nudged.cars[0].state.position.x = nudged.cars[0].state.position.x.nextUp
        XCTAssertNotEqual(nudged.stateHash, base, "a one-ULP difference must be visible")
    }

    func testHasherIsOrderSensitiveAndNotSeededPerProcess() {
        // Swift's own Hasher is randomly seeded per process, which is precisely
        // the property a cross-device comparison must not have. FNV-1a is spelled
        // out for that reason; pin the arithmetic so a "cleanup" cannot swap it
        // back for the standard library's.
        var a = Hasher64()
        var b = Hasher64()
        a.combine(1)
        a.combine(2)
        b.combine(2)
        b.combine(1)
        XCTAssertNotEqual(a.value, b.value, "hash must depend on order")

        var empty = Hasher64()
        XCTAssertEqual(empty.value, 0xcbf2_9ce4_8422_2325, "FNV-1a offset basis")
        empty.combineByte(0)
        XCTAssertEqual(
            empty.value, Hasher64.offsetBasis &* Hasher64.prime,
            "a zero byte still multiplies: XOR with 0 leaves the basis")
        XCTAssertEqual(
            Hasher64.prime, 1_099_511_628_211, "the 64-bit FNV prime, not the 32-bit one")

        // Width is not interchangeable: one byte must not consume eight. This
        // caught a real overload-resolution bug, where `combine(UInt8(0))`
        // widened to UInt64 and hashed eight zero bytes.
        var oneByte = Hasher64()
        var eightBytes = Hasher64()
        oneByte.combineByte(0)
        eightBytes.combine(UInt64(0))
        XCTAssertNotEqual(oneByte.value, eightBytes.value)
    }

    // MARK: - The cross-device tripwire

    /// **The float-determinism assumption, pinned as a number.**
    ///
    /// IEEE-754 fixes `+ - * /` and `sqrt` exactly but says nothing about
    /// transcendentals, and the sim calls `sin`/`cos`/`atan2`/`pow` on its hot
    /// path. So "two devices compute the same race" is an *assumption*, and this
    /// is what converts it into something that can fail loudly.
    ///
    /// It passes trivially today and that is the point: it is a tripwire, not a
    /// discovery. The moment a new Xcode, a different libm, or another
    /// architecture disagrees, this goes red and names the tick.
    ///
    /// **If it fails, do not just re-pin the number.** Find out what changed
    /// first — that is the entire value here. A legitimate physics change requires
    /// re-pinning (and the other tests in this file prove the sim still agrees
    /// with itself); a *platform* difference is the thing lockstep networking
    /// cannot survive, and re-pinning would hide it.
    ///
    /// **Re-pinned a fourth time, deliberately**: the compiler gained a run-off
    /// margin (`PieceCompiler.runOff`), which TRANSLATES every compiled track —
    /// and `testRing` is the compiled "small" builtin. Positions are absolute,
    /// so every hash moved, tick 1 included: unlike the physics re-pins, the
    /// countdown's stillness is no alibi here, because the cars were placed a
    /// road width further in before the first tick. A translation, not a
    /// physics change and not a platform one.
    ///
    /// **Re-pinned a third time, deliberately**: `speedGripFade` (0.5 stock)
    /// made grip fall with speed, so fast corners hold their slide — a device
    /// feel request. Physics change, same evidence as before: tick 1's hash
    /// is untouched because the countdown holds every car still.
    ///
    /// **Re-pinned a second time, deliberately**: the stock car tuning changed
    /// after device play (aim flip rate 10→7, speed boost 8→7, drift retention
    /// 1.0→0.6, grip 1.0→0.8, wall bounce 0.40→0.30). A tuning change is a
    /// change to the physics being stepped, so every hash after the countdown
    /// moved — and tick 1's did NOT, which is the evidence it is a physics
    /// change and not the platform difference this test exists to catch: the
    /// countdown holds every car still, so nothing tuning touches has happened
    /// yet.
    ///
    /// **Re-pinned once, deliberately**: `Race.advance` began quantising its inputs, so
    /// every hash moved. That is a change to what the sim steps rather than to how it
    /// steps, it is the same on every platform, and it is what lets a lap be stored as four
    /// bytes a tick and still replay the line that was driven.
    func testAFixedScriptProducesAKnownHashSequence() {
        let sequence = hashes(seed: 42, ticks: 600)
        // Sampled rather than pinned whole: 600 literals would be unreadable, and
        // the sampled ticks span the countdown, the first corner and settled
        // driving. Any divergence propagates, so a late sample catches an early one.
        let samples = [1, 30, 60, 120, 300, 599].map { sequence[$0 - 1] }
        XCTAssertEqual(
            samples,
            [
                8_168_309_041_451_275_334, 15_062_452_510_356_021_344,
                8_788_705_495_310_688_251,
                1_864_096_498_505_380_116, 8_827_391_443_098_983_015,
                12_618_885_254_617_686_516,
            ])
        XCTAssertEqual(sequence.count, 600)
    }
}
