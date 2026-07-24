import XCTest

@testable import SkidCore

/// Live race positions: `Race.standings` ranks cars best-first, deterministic
/// off sim state. Finished cars lead (by finish time), the rest by how far
/// around they are, then distance to the next gate; ties break by car index.
final class StandingsTests: XCTestCase {
    private func loopTrack() -> Track {
        // A wide oval-ish loop with four directional gates around it.
        Track(
            centerline: [Vec2(-1000, -500), Vec2(1000, -500), Vec2(1000, 500), Vec2(-1000, 500)],
            width: 400,
            gates: [
                Gate(from: Vec2(0, -700), to: Vec2(0, -300), forward: Vec2(1, 0)),
                Gate(from: Vec2(1200, 0), to: Vec2(800, 0), forward: Vec2(0, 1)),
                Gate(from: Vec2(0, 300), to: Vec2(0, 700), forward: Vec2(-1, 0)),
                Gate(from: Vec2(-1200, 0), to: Vec2(-800, 0), forward: Vec2(0, -1)),
            ],
            startSlots: [Vec2(-100, -500), Vec2(-300, -500), Vec2(-500, -500)],
            size: Vec2(4000, 4000))
    }

    private func race(_ n: Int) -> Race {
        Race(
            track: loopTrack(), players: (0..<n).map(PlayerID.init),
            config: RaceConfig(laps: 3, countdownTicks: 0))
    }

    func testMoreGatesCrossedRanksAhead() {
        var r = race(2)
        r.cars[0].progress.nextGate = 1  // car 0 has crossed one gate
        r.cars[1].progress.nextGate = 3  // car 1 has crossed three
        XCTAssertEqual(r.standings, [1, 0])  // car 1 leads
    }

    func testMoreLapsRanksAheadOfMoreGates() {
        var r = race(2)
        r.cars[0].progress.lap = 1
        r.cars[0].progress.nextGate = 0  // one full lap in
        r.cars[1].progress.nextGate = 3  // still on lap 0
        XCTAssertEqual(r.standings, [0, 1])
    }

    func testSameGateBreaksByDistanceToNextGate() {
        var r = race(2)
        // Both cars between gate 0 and gate 1 (next gate = 1, at x≈1000).
        r.cars[0].progress.nextGate = 1
        r.cars[1].progress.nextGate = 1
        r.cars[0].state.position = Vec2(200, -500)  // far from gate 1
        r.cars[1].state.position = Vec2(900, -400)  // nearly at gate 1
        XCTAssertEqual(r.standings, [1, 0])  // closer car leads
    }

    func testFinishedCarsLeadUnfinishedByFinishTime() {
        var r = race(3)
        r.cars[0].progress.finishedAt = 500
        r.cars[2].progress.finishedAt = 400  // finished earlier → P1
        // car 1 unfinished, but well along
        r.cars[1].progress.lap = 2
        r.cars[1].progress.nextGate = 3
        XCTAssertEqual(r.standings, [2, 0, 1])
    }

    func testTiesBreakByCarIndexForStability() {
        var r = race(3)
        // Force an exact tie: same gate, same position → identical progress.
        for i in r.cars.indices {
            r.cars[i].progress.nextGate = 1
            r.cars[i].state.position = Vec2(500, -500)
        }
        XCTAssertEqual(r.standings, [0, 1, 2])  // stable, by index
    }
}
