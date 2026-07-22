import XCTest

@testable import SkidCore

/// Every built-in track must clear the same bar — adding a track means
/// passing these, nothing less.
final class TrackLibraryTests: XCTestCase {
    func testRosterAndLookup() {
        let ids = TrackLibrary.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "track ids must be unique")
        XCTAssertFalse(ids.contains(""), "every track needs a stable id")
        for id in ids {
            XCTAssertEqual(TrackLibrary.track(id: id).id, id)
        }
        XCTAssertEqual(TrackLibrary.track(id: "no-such").id, "practice-loop")
    }

    func testEveryTrackIsWellFormed() {
        for track in TrackLibrary.all {
            XCTAssertGreaterThanOrEqual(track.gates.count, 3, track.id)
            XCTAssertEqual(track.startSlots.count, 4, track.id)
            XCTAssertEqual(track.walls.count, 4, track.id)
            for gate in track.gates {
                XCTAssertGreaterThan(
                    gate.forward.lengthSquared, 0, "\(track.id): gates must be directional")
                XCTAssertNotNil(
                    track.ribbonSpan(of: gate), "\(track.id): every gate paints on the road")
            }
            for slot in track.startSlots {
                XCTAssertEqual(
                    track.surface(at: slot), .asphalt, "\(track.id): grid slot off the ribbon")
            }
            for patch in track.patches {
                XCTAssertLessThanOrEqual(
                    track.distanceToCenterline(patch.center),
                    track.width / 2 + patch.radius,
                    "\(track.id): hazard nowhere near the racing line"
                )
            }
            // Driving forward from pole crosses the start/finish gate.
            let pole = track.startSlots[0]
            let ahead = pole + Vec2(angle: track.startHeading) * 400
            XCTAssertTrue(
                track.gates.last!.crossedForward(movingFrom: pole, to: ahead), track.id)
        }
    }

    /// The real bar: a default AI driver can lap every track, gates and
    /// all, in a sane time. If a new track breaks the AI, the track (or
    /// the AI) isn't done.
    func testAICanLapEveryTrack() {
        for track in TrackLibrary.all {
            var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
            var driver = AIDriver()
            var ticks = 0
            while race.cars[0].progress.finishedAt == nil, ticks < 120 * Race.tickRate {
                let input = driver.input(car: race.cars[0].state, track: race.track)
                race.advance(inputs: [PlayerID(0): input])
                ticks += 1
            }
            let progress = race.cars[0].progress
            XCTAssertNotNil(
                progress.finishedAt,
                "\(track.id): AI stuck (gate \(progress.nextGate), lap \(progress.lap))"
            )
        }
    }
}
