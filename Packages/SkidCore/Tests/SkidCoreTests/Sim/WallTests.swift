import XCTest

@testable import SkidCore

/// Barriers around elevated road: the rails along a bridge and its ramps, the map
/// boundary, and what each of them does or doesn't stop.
final class WallTests: XCTestCase {
    /// **You can't hop onto a ramp from the grass beside it.** Reported as
    /// "I can jump on the bridge/ramp from the grass, both from under the bridge
    /// and from the sides, across the walls — more often than not".
    ///
    /// Two causes, both fixed: the rails were placed at the height-SCALED road
    /// width, so they drifted outboard as the ramp climbed (0.2 units off the edge
    /// at the foot, 8+ by mid-ramp); and a rail only blocked a car at its own
    /// height, so the mid-ramp rails (around 0.5) matched neither a ground car nor
    /// a deck car and stopped nobody.
    func testARampCannotBeEnteredFromItsFlank() throws {
        let track = TrackLibrary.track(id: "eight")
        let count = track.centerline.count
        var attempts = 0
        for index in track.centerline.indices {
            let next = (index + 1) % count
            guard abs(track.heights[next] - track.heights[index]) > 0.02 else { continue }
            // Skip the ramp's own mouth — driving in there is the point of a ramp.
            guard track.heights[index] > 0.05 else { continue }
            let a = track.centerline[index]
            let b = track.centerline[next]
            let mid = a + (b - a) * 0.5
            let side = (b - a).normalized.perpendicular
            for direction in [1.0, -1.0] {
                attempts += 1
                var race = Race(track: track, players: [PlayerID(0)])
                let start = mid + side * (track.width / 2 + 100) * direction
                let aim = (mid - start).normalized
                race.cars[0].state.position = start
                race.cars[0].state.height = 0
                race.cars[0].state.heading = atan2(aim.y, aim.x)
                race.cars[0].state.velocity = aim * 400
                for _ in 0..<90 {
                    race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
                }
                XCTAssertLessThan(
                    race.cars[0].state.height, 0.3,
                    "climbed the ramp from its flank at segment \(index), side \(direction)")
            }
        }
        XCTAssertGreaterThan(attempts, 10, "fixture must have a ramp with flanks to test")
    }

    /// Rails sit on the road's TRUE edge, not the height-scaled visual one — the
    /// grip width never scales with height, so a scaled rail sits somewhere the
    /// car can't reach.
    /// **A car stops against the railing you can see, not the line behind it.**
    ///
    /// A rail is a segment in the model but a band on screen, `kerbBand` of it
    /// outboard of the asphalt. Coming from the grass the car used to halt with
    /// its centre a car-radius from that inner line, which left it stopped in
    /// mid-air short of the barrier — measured at a clover ramp root, a 4.9-unit
    /// gap. From INSIDE nothing changes: the band's inner half hides under the
    /// asphalt, so the segment already is the face there.
    func testACarStopsAgainstTheRailingItCanSee() throws {
        let layout = try XCTUnwrap(TrackLibrary.layout(id: "clover"))
        let track = try PieceCompiler.compile(layout, id: "clover")
        // Both a deck rail and a ramp-ROOT rail: the band's stand-off grows with
        // height, so one figure for all of them gave the low rails 12 units of
        // invisible reach ("the car leans against nothing at the ramp's root").
        for minHeight in [0.9, 0.0] {
            try assertStopsAgainstItsBand(on: track, railAbove: minHeight)
        }
    }

    private func assertStopsAgainstItsBand(on track: Track, railAbove: Double) throws {
        let rail = try XCTUnwrap(
            track.walls.first {
                $0.kind == .rail && $0.outward.length > 0.001
                    && $0.height > railAbove && $0.height < railAbove + 0.1
                    && ($0.b - $0.a).length < Double(PieceCatalog.width)
            }, "the clover should have a rail just above \(railAbove)")
        let mid = (rail.a + rail.b) * 0.5

        var race = Race(
            track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
        // Approach from OUTSIDE, at the rail's own height, driving inward.
        let start = mid + rail.outward * 40
        race.cars[0].state.position = start
        race.cars[0].state.height = rail.height
        race.cars[0].state.velocity = rail.outward * -120
        // The CLOSEST it ever gets: a wall has restitution, so the car bounces
        // away again and its final rest position is not where it touched.
        var closest = Double.greatestFiniteMagnitude
        for _ in 0..<20 {
            race.advance(inputs: [PlayerID(0): .coast])
            closest = min(closest, (race.cars[0].state.position - mid).dot(rail.outward))
        }
        let standoff = closest

        // It must stop clear of the band's outboard face, not just the segment.
        let bandFace =
            track.halfWidth(atHeight: rail.height) + Double(PieceCatalog.kerbBand)
            - track.width / 2
        XCTAssertGreaterThan(
            standoff, bandFace,
            "at h \(rail.height) the car stopped inside the railing's drawn band")
        // And snug against it: the car's own radius past the band's face, no
        // more, so the barrier is exactly as thick as it is drawn — no
        // invisible reach beyond the picture.
        XCTAssertLessThan(
            standoff, bandFace + CarGeometry.radius + 2,
            "at h \(rail.height) the car stopped short of the railing")
    }

    /// The face is **stored**, not inferred, and the compiler gets it right:
    /// stepping along a rail's `outward` must lead away from the road it guards.
    /// Deriving it instead was measured wrong for 192 of the clover's 430 rails
    /// ("away from the middle of the map" fails wherever a track curls back).
    func testEveryRailKnowsWhichWayIsOut() throws {
        for id in ["eight", "clover"] {
            let layout = try XCTUnwrap(TrackLibrary.layout(id: id))
            let track = try PieceCompiler.compile(layout, id: id)
            var checked = 0
            for wall in track.walls
            where wall.kind == .rail && wall.outward.length > 0.001 {
                // End caps span the road across, so "out" has no meaning there.
                guard (wall.b - wall.a).length < Double(PieceCatalog.width) else {
                    continue
                }
                let mid = (wall.a + wall.b) * 0.5
                let inward = track.distanceToCenterline(mid - wall.outward * 10)
                let outward = track.distanceToCenterline(mid + wall.outward * 10)
                XCTAssertGreaterThan(
                    outward, inward,
                    "\(id): a rail's outward must point away from its road")
                checked += 1
            }
            XCTAssertGreaterThan(checked, 0, "\(id) should have faced rails")
        }
    }

    func testRailsSitOnTheRealRoadEdge() {
        let track = TrackLibrary.track(id: "eight")
        let count = track.centerline.count
        var checked = 0
        for index in track.centerline.indices {
            let next = (index + 1) % count
            guard abs(track.heights[next] - track.heights[index]) > 0.02 else { continue }
            let a = track.centerline[index]
            let b = track.centerline[next]
            let mid = a + (b - a) * 0.5
            let side = (b - a).normalized.perpendicular
            // The road edge AT THIS HEIGHT: the ribbon widens as it rises, so a
            // flat `width / 2` is the wrong edge to compare a rail against —
            // that assumption is what left rails inboard of the visible asphalt
            // (36 units of transparent wall at height 3).
            let height = (track.heights[index] + track.heights[next]) / 2
            let edge = mid + side * track.halfWidth(atHeight: height)
            let nearest =
                track.walls.filter { $0.kind == .rail }
                .map { edge.distance(toSegment: $0.a, $0.b) }.min() ?? .greatestFiniteMagnitude
            XCTAssertLessThan(nearest, 2, "the rail at segment \(index) is off the road edge")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "fixture must contain a ramp")
    }

    /// A fast car can't tunnel through a wall between ticks: collision is swept
    /// against the whole movement, not just the end position.
    func testAFastCarCannotTunnelThroughTheBoundary() {
        let track = TrackLibrary.track(id: "eight")
        var race = Race(track: track, players: [PlayerID(0)])
        // Aim at the map's edge at an absurd speed.
        race.cars[0].state.position = Vec2(track.size.x / 2, 60)
        race.cars[0].state.heading = -.pi / 2
        race.cars[0].state.velocity = Vec2(0, -4000)
        for _ in 0..<30 {
            race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
        }
        XCTAssertGreaterThan(
            race.cars[0].state.position.y, -CarGeometry.radius,
            "the car tunnelled straight through the boundary fence")
    }

    /// **The road under a bridge stays open.** A deck rail must not wall off the
    /// road passing beneath it.
    ///
    /// This regressed when rails were made to block every car at or below their
    /// height (fixing the hop-onto-the-ramp gap): a deck rail at 1.0 then also
    /// blocked a ground car. A rail blocks from its own level's floor up to its
    /// height — floor 1 for a deck rail, floor 0 for a mid-ramp one — so the ramp
    /// stays fenced while the road below runs clear.
    func testTheRoadUnderTheBridgeIsNotWalledOff() throws {
        let track = TrackLibrary.track(id: "eight")
        let count = track.centerline.count
        let under = try XCTUnwrap(
            track.centerline.indices.first { index in
                track.height(ofSegment: index) < 0.1
                    && track.distanceToCenterline(track.centerline[index], height: 1) < track.width
            })
        var race = Race(track: track, players: [PlayerID(0)])
        let start = track.centerline[(under + count - 4) % count]
        let aim = (track.centerline[(under + 4) % count] - start).normalized
        race.cars[0].state.position = start
        race.cars[0].state.height = 0
        race.cars[0].state.heading = atan2(aim.y, aim.x)
        for _ in 0..<120 {
            race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
            for event in race.lastEvents {
                if case .wallImpact = event {
                    XCTFail("a car driving under the bridge hit a wall")
                }
            }
        }
        XCTAssertGreaterThan(
            start.distance(to: race.cars[0].state.position), track.width * 2,
            "the car should have driven clear through, under the bridge")
    }

    /// **You cannot drive under a ramp.** Specced by the maintainer: a ramp should
    /// act as though it had a wall across its high end, at a height below the deck,
    /// meeting the side rails with no gap at the corners.
    ///
    /// The high end is what needs it. A ramp rises off the ground, so the space
    /// beneath its upper reaches is open air, and driving in there is driving
    /// through the embankment. The cap sits at 0.99: under the wall rule
    /// (`Race.blocks`, floor = trunc(height)) that blocks 0…0.99 — everything below
    /// the deck — while a car arriving along the ramp at deck height passes.
    func testYouCannotDriveUnderARamp() {
        let track = TestTracks.steepBridge()
        let count = track.centerline.count
        var blockedFromOutside = 0
        var allowedUpTheRamp = 0
        for index in track.centerline.indices {
            let next = (index + 1) % count
            guard abs(track.heights[next] - track.heights[index]) > 0.05,
                track.heights[index] > 0.6
            else { continue }
            let point = track.centerline[index]
            let along = (track.centerline[next] - point).normalized
            let climbDirection =
                track.heights[next] > track.heights[index]
                ? along : Vec2(-along.x, -along.y)
            for direction in [1.0, -1.0] {
                var race = Race(track: track, players: [PlayerID(0)])
                let start = point + along * 200 * direction
                let aim = (point - start).normalized
                race.cars[0].state.position = start
                race.cars[0].state.height = 0
                race.cars[0].state.heading = atan2(aim.y, aim.x)
                race.cars[0].state.velocity = aim * 400
                var reached = false
                for _ in 0..<90 {
                    race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
                    // "Reached" means OCCUPYING the raised road, one car radius.
                    // Half a road width read as reached before, which failed a
                    // car legitimately parked nose-first against the mouth seal
                    // just outside it — the seal sits ON the road's footprint,
                    // so a blocked car stops well inside that radius.
                    if race.cars[0].state.position.distance(to: point) < CarGeometry.radius {
                        reached = true
                        break
                    }
                }
                // Coming up the ramp is the way in; coming at its raised end from
                // outside is driving under it, and must be stopped.
                if aim.dot(climbDirection) > 0 {
                    if !reached { allowedUpTheRamp += 0 } else { allowedUpTheRamp += 1 }
                } else {
                    XCTAssertFalse(
                        reached,
                        "drove under the raised end of the ramp at segment \(index)")
                    blockedFromOutside += 1
                }
            }
        }
        XCTAssertGreaterThan(blockedFromOutside, 0, "fixture must have a raised ramp end")
        XCTAssertGreaterThan(allowedUpTheRamp, 0, "the ramp must still be drivable")
    }

    /// The cap spans the full road width, meeting the side rails at their own
    /// endpoints, so there's no gap to squeeze through at either corner.
    func testRampCapsMeetTheSideRailsWithoutGaps() {
        let track = TrackLibrary.track(id: "eight")
        let rails = track.walls.filter { $0.kind == .rail }
        // A cap is a wall roughly a full road width long; a side rail is short.
        let caps = rails.filter { ($0.b - $0.a).length > track.width * 0.9 }
        XCTAssertFalse(caps.isEmpty, "a ramp should be capped at both ends")
        for cap in caps {
            for corner in [cap.a, cap.b] {
                // Some other rail must start or end at this exact corner.
                let met = rails.contains { other in
                    guard other != cap else { return false }
                    return (other.a - corner).length < 0.5 || (other.b - corner).length < 0.5
                }
                XCTAssertTrue(met, "cap corner \(corner) doesn't meet a side rail")
            }
        }
    }
}
