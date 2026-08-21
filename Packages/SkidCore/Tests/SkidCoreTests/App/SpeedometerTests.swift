import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The speedometer as the screen actually builds it.**
///
/// `WorldScaleTests` pins the arithmetic; this pins the WIRING, which is where
/// this feature has gone wrong before: a readout can be correct in every unit
/// test while the view hands it the wrong number. Swapping the signed forward
/// speed for `velocity.length` broke reverse and failed nothing until this
/// existed.
@MainActor
final class SpeedometerTests: XCTestCase {
    private func game() -> CouchGame {
        CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "speedo-\(UUID().uuidString).json",
            profileFilename: "speedo-\(UUID().uuidString).json",
            setupFilename: "speedo-\(UUID().uuidString).json")
    }

    /// Build the zone chrome the way `RaceScreen` does, and read the label out
    /// of it — the closest a headless test gets to the pixels.
    private func chrome(for couch: CouchGame) throws -> [ZoneChrome] {
        let session = try XCTUnwrap(couch.session)
        let rig = try XCTUnwrap(couch.rig)
        let units = couch.settings.units
        return rig.players.map { controls -> ZoneChrome in
            let car = session.race.cars.first { $0.id == controls.player }
            return ZoneChrome(
                rect: controls.zone, up: controls.up,
                color: CouchGame.palette[controls.colorIndex],
                safeInsets: EdgeInsets(),
                speed: car.map { ZoneChrome.speedLabel(for: $0.state, in: units) })
        }
    }

    /// **Every player gets their own**, one per control box.
    func testEachPlayerHasATheirOwnReadout() throws {
        let couch = game()
        couch.playerCount = 2
        couch.startRace()
        let zones = try chrome(for: couch)
        XCTAssertEqual(zones.count, 2)
        XCTAssertTrue(zones.allSatisfy { $0.speed != nil })
        // Distinct colors, so each reads as belonging to its own box.
        XCTAssertNotEqual(zones[0].color, zones[1].color)
    }

    /// A race whose single car is driven by a fixed input, so it can be brought
    /// to a genuinely reversing state — `race` is read-only from out here
    /// (rightly: nothing outside should teleport a car), so the sim is the only
    /// route to one.
    private func driven(throttle: Double, seconds: Double) -> Race {
        let track = TrackLibrary.track(id: "oval")
        var race = Race(
            track: track, players: [PlayerID(0)],
            config: RaceConfig(laps: nil, countdownTicks: 0))
        let input = CarInput(steer: 0, throttle: throttle)
        for _ in 0..<Int(seconds * Double(Race.tickRate)) {
            race.advance(inputs: [PlayerID(0): input])
        }
        return race
    }

    /// The label the zone chrome would carry for a car, built the way
    /// `RaceScreen.zoneChrome` builds it.
    private func label(for car: Car, units: WorldScale.Units = .metric) -> String {
        ZoneChrome.speedLabel(for: car.state, in: units)
    }

    /// **Reverse shows a negative number**, which is the whole reason the
    /// readout is the signed forward speed rather than the velocity's length.
    func testReversingShowsANegativeNumber() throws {
        let car = driven(throttle: -1, seconds: 5).cars[0]
        XCTAssertLessThan(
            car.state.velocity.dot(car.state.forward), 0,
            "fixture: the car is not actually reversing")
        // A magnitude would have called this positive — the whole point.
        XCTAssertGreaterThan(car.state.velocity.length, 0)
        XCTAssertTrue(
            label(for: car).hasPrefix("-"),
            "reversing showed \(label(for: car)) — a magnitude cannot say 'backwards'")
    }

    /// And forwards is positive, so the sign tracks direction rather than
    /// always being negative.
    func testDrivingForwardShowsAPositiveNumber() throws {
        // One second, not five: the oval's start straight runs out and the car
        // parks against the far wall, where it honestly reads 0.
        let car = driven(throttle: 1, seconds: 1).cars[0]
        let shown = label(for: car)
        XCTAssertFalse(shown.hasPrefix("-"), "going forwards showed \(shown)")
        XCTAssertNotEqual(shown, "0 km/h", "the car never moved")
    }

    /// The readout follows the units setting, so an imperial player sees mph on
    /// their own box too — not just in the editor.
    func testTheReadoutFollowsTheUnitsSetting() throws {
        let car = driven(throttle: 1, seconds: 3).cars[0]
        XCTAssertTrue(label(for: car, units: .metric).hasSuffix("km/h"))
        XCTAssertTrue(label(for: car, units: .imperial).hasSuffix("mph"))
    }
}
