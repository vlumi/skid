import XCTest

@testable import SkidCore

/// The sim's foundational promise: same inputs → same states, bit-for-bit.
/// Replays, ghosts, and lockstep networking all stand on this.
final class DeterminismTests: XCTestCase {
    private func scriptedInput(player: PlayerID, tick: Tick) -> CarInput {
        // A deterministic, wiggly script exercising steer, gas, brake, and
        // coast across surfaces and wall contact.
        let phase = Double(tick) / 60.0
        let steer = sin(phase * 1.7 + Double(player.rawValue))
        let throttle: Double
        switch tick % 240 {
        case 0..<160: throttle = 1
        case 160..<200: throttle = 0
        default: throttle = -1
        }
        return CarInput(steer: steer, throttle: throttle)
    }

    /// Runs the script, returning the final state and the per-tick hash trail.
    private func runRace(seed: UInt64, ticks: Int) -> (race: Race, hashes: [UInt64]) {
        let players = [PlayerID(0), PlayerID(1), PlayerID(2), PlayerID(3)]
        var race = Race(track: TrackLibrary.testRing(), players: players, seed: seed)
        var hashes: [UInt64] = []
        for _ in 0..<ticks {
            var inputs: [PlayerID: CarInput] = [:]
            for player in players {
                inputs[player] = scriptedInput(player: player, tick: race.tick)
            }
            race.advance(inputs: inputs)
            hashes.append(race.stateHash)
        }
        return (race, hashes)
    }

    func testIdenticalRunsProduceIdenticalStates() {
        let a = runRace(seed: 42, ticks: 1800)  // 30 sim-seconds, 4 cars
        let b = runRace(seed: 42, ticks: 1800)

        // **Report the first diverging TICK, not just that 1800 of them differ.**
        // `XCTAssertEqual(a, b)` on the races dumps two whole `Race` values and
        // leaves the question "since when?" — which is the expensive part of the
        // debugging. The hash trail answers it before the state comparison runs.
        if let tick = Array(zip(a.hashes, b.hashes)).firstIndex(where: { $0 != $1 }) {
            XCTFail("runs diverged at tick \(tick) of 1800")
        }
        XCTAssertEqual(a.race, b.race)
        // Sanity: the script actually moved the cars off the grid.
        XCTAssertNotEqual(a.race.cars[0].state.position, TrackLibrary.testRing().startSlots[0])
    }

    func testGridShuffleIsAValidPermutationAndSeedStable() {
        let track = TrackLibrary.testRing()
        let players = [PlayerID(0), PlayerID(1), PlayerID(2), PlayerID(3)]
        let slots = Set(track.startSlots.prefix(players.count))

        // Every car lands on a distinct real start slot — a permutation, no
        // two cars stacked, none off-grid.
        let race = Race(track: track, players: players, seed: 3)
        let placed = race.cars.map(\.state.position)
        XCTAssertEqual(Set(placed).count, players.count, "two cars share a slot")
        for position in placed { XCTAssertTrue(slots.contains(position), "car off-grid") }

        // Same seed → same grid (replays/ghosts stay exact).
        let again = Race(track: track, players: players, seed: 3)
        XCTAssertEqual(placed, again.cars.map(\.state.position))
    }

    func testGridShufflePreservesCarIdentity() {
        // The shuffle moves POSITIONS, not identities: cars[i] is still
        // player i (so HUD chips + colors, keyed by index, stay correct).
        let players = [PlayerID(0), PlayerID(1), PlayerID(2), PlayerID(3)]
        let race = Race(track: TrackLibrary.testRing(), players: players, seed: 9)
        XCTAssertEqual(race.cars.map(\.id), players)
    }

    func testMissingInputsCoast() {
        var race = Race(track: TrackLibrary.testRing(), players: [PlayerID(0)])
        race.advance(inputs: [:])
        XCTAssertEqual(race.tick, 1)
    }

    func testSeededRNGIsReproducible() {
        var a = SeededRNG(seed: 7)
        var b = SeededRNG(seed: 7)
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next())
        }
        var c = SeededRNG(seed: 8)
        var d = SeededRNG(seed: 7)
        XCTAssertNotEqual(d.next(), c.next())
    }
}
