import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **"Which car is mine" exists exactly while it is needed** — the countdown,
/// where identical silhouettes sit still on the grid — and each marker carries
/// what the drawing needs: the car's SCREEN position (the small halo worn on the
/// car), where its leader line leaves the player's own band, and the color.
@MainActor
final class GridMarkerTests: XCTestCase {
    private let mapRect = CGRect(x: 0, y: 300, width: 800, height: 600)

    private func rig(colorIndices: [Int], seats: [PlayerID]? = nil) -> CouchRig {
        let rig = CouchRig(colorIndices: colorIndices, seats: seats)
        rig.layout(size: CGSize(width: 800, height: 1200), mapRect: mapRect)
        return rig
    }

    private func race(players: Int) -> Race {
        Race(
            track: TrackLibrary.track(id: "oval"), players: (0..<players).map(PlayerID.init),
            config: RaceConfig(laps: 3, countdownTicks: 120))
    }

    func testMarkersExistOnlyDuringTheCountdown() {
        var race = race(players: 1)
        let rig = rig(colorIndices: [0])
        guard case .countdown = race.phase else {
            return XCTFail("a fresh race must start in countdown")
        }
        XCTAssertEqual(
            GridMarkers.markers(
                race: race, players: rig.players, mapRect: mapRect,
                palette: CouchGame.palette
            ).count, 1)
        // Run the countdown out; the markers must leave with it.
        while case .countdown = race.phase {
            race.advance(inputs: [:])
        }
        XCTAssertTrue(
            GridMarkers.markers(
                race: race, players: rig.players, mapRect: mapRect,
                palette: CouchGame.palette
            ).isEmpty, "the marker outlived the countdown")
    }

    /// Each halo sits on its own car, and each leader line leaves its OWN
    /// player's band by the map-side edge — a line from the wrong edge would tie
    /// the car to the wrong corner of the table.
    func testHalosSitOnTheirCarsAndLeadersLeaveTheirOwnBand() {
        let track = TrackLibrary.track(id: "oval")
        let race = Race(
            track: track, players: [PlayerID(0), PlayerID(1)],
            config: RaceConfig(laps: 3, countdownTicks: 120))
        let rig = rig(colorIndices: [0, 1])
        let markers = GridMarkers.markers(
            race: race, players: rig.players, mapRect: mapRect, palette: CouchGame.palette)
        XCTAssertEqual(markers.count, 2)
        // Screen position = mapRect origin + world position * fitted scale.
        let scale = mapRect.width / track.size.x
        let expected = race.cars[0].state.position * scale + Vec2(mapRect.minX, mapRect.minY)
        XCTAssertEqual(markers[0].position.x, expected.x, accuracy: 1e-9)
        XCTAssertEqual(markers[0].position.y, expected.y, accuracy: 1e-9)
        for (marker, controls) in zip(markers, rig.players) {
            let zone = controls.zone
            let edge = Vec2(zone.midX, zone.midY) + controls.up * (zone.height / 2)
            XCTAssertEqual(marker.leaderStart.x, edge.x, accuracy: 1e-9)
            XCTAssertEqual(
                marker.leaderStart.y, edge.y, accuracy: 1e-9,
                "the leader must leave the band's map-side edge")
        }
    }

    /// A networked guest drives global seats (say 2 and 3) — the markers must
    /// follow the SEAT's cars, not the local band index's.
    func testMarkersFollowGlobalSeatsOnAGuestDevice() {
        let race = race(players: 4)
        let rig = rig(colorIndices: [2, 3], seats: [PlayerID(2), PlayerID(3)])
        let markers = GridMarkers.markers(
            race: race, players: rig.players, mapRect: mapRect, palette: CouchGame.palette)
        let scale = mapRect.width / race.track.size.x
        XCTAssertEqual(markers.count, 2)
        for (marker, seat) in zip(markers, [2, 3]) {
            let expected =
                race.cars.first { $0.id == PlayerID(seat) }!.state.position * scale
                + Vec2(mapRect.minX, mapRect.minY)
            XCTAssertEqual(
                marker.position.x, expected.x, accuracy: 1e-9,
                "a guest's marker must sit on its own seat's car")
            XCTAssertEqual(marker.position.y, expected.y, accuracy: 1e-9)
        }
    }
}
