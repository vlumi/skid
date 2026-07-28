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

    /// **The score never decreases as a car advances along the route.** The
    /// old straight-line fraction inverted inside the clover's loops (a car
    /// entering a loop is geometrically closer to the gate beyond it than a
    /// car ahead of it rounding the head), which is exactly where players
    /// watched positions swap wrongly. Walk a probe car along every
    /// centerline point of a full lap with the correct next gate, and require
    /// monotone progress.
    func testProgressIsMonotoneAlongTheLap() throws {
        let track = try XCTUnwrap(TrackLibrary.track(id: "clover"))
        let race = Race(
            track: track, players: [PlayerID(0)], config: RaceConfig(laps: 3))
        // Each gate's position along the lap, in route order of crossing.
        let gateArcs = track.gates.map {
            track.arcPosition(of: ($0.a + $0.b) * 0.5, preferHeight: $0.height)
        }
        var previous = -Double.infinity
        var car = race.cars[0]
        // Exact arc per point: the cumulative length up to it. (Querying
        // `arcPosition` blind at a crossing point can snap to the OTHER road;
        // the walk must stay on its own route.)
        var arcs: [Double] = [0]
        for i in 1..<track.centerline.count {
            arcs.append(arcs[i - 1] + track.centerline[i - 1].distance(to: track.centerline[i]))
        }
        for index in track.centerline.indices {
            car.state.position = track.centerline[index]
            car.state.height = track.heights[index]
            // The next gate is the first one still ahead along the route.
            car.progress.nextGate =
                gateArcs.enumerated().filter { $0.element > arcs[index] + 0.001 }
                .min { $0.element < $1.element }?.offset ?? 0
            let score = race.raceProgress(of: car)
            // Past the last gate, nextGate wraps to 0 and the synthetic walk
            // (which never earns the lap) legitimately resets — compare only
            // within the lap body.
            if car.progress.nextGate != 0 {
                XCTAssertGreaterThanOrEqual(
                    score, previous - 1e-9,
                    "progress went backward at centerline point \(index)")
                previous = score
            } else {
                previous = -Double.infinity
            }
        }
    }

    /// The reported scene, concretely: two cars between the same gates, the
    /// leader farther along the road — the leader must rank ahead even where
    /// the trailing car is geometrically closer to the gate.
    func testTheCarAheadOnTheRoadRanksAhead() throws {
        let track = try XCTUnwrap(TrackLibrary.track(id: "clover"))
        var race = Race(
            track: track, players: [PlayerID(0), PlayerID(1)],
            config: RaceConfig(laps: 3))
        let gate = track.gates[0]
        let gateArc = track.arcPosition(
            of: (gate.a + gate.b) * 0.5, preferHeight: gate.height)
        // Two points on the approach to gate 0: `lead` strictly farther along
        // the road, both with the gate still ahead.
        func point(atArcBack back: Double) -> Int {
            track.centerline.indices.min {
                abs(arcAhead(from: $0, to: gateArc, in: track) - back)
                    < abs(arcAhead(from: $1, to: gateArc, in: track) - back)
            }!
        }
        let trail = point(atArcBack: 700)
        let lead = point(atArcBack: 250)
        for (car, index) in [(0, trail), (1, lead)] {
            race.cars[car].state.position = track.centerline[index]
            race.cars[car].state.height = track.heights[index]
            race.cars[car].progress.nextGate = 0
            race.cars[car].progress.lap = 1
        }
        XCTAssertEqual(
            race.standings, [1, 0],
            "the car farther along the road must rank ahead")
    }

    /// Forward distance along the loop from a centerline point to an arc mark.
    private func arcAhead(from index: Int, to gateArc: Double, in track: Track) -> Double {
        let arc = track.arcPosition(of: track.centerline[index])
        let ahead = gateArc - arc
        return ahead < 0 ? ahead + track.centerlineLength : ahead
    }
}
