import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **"Which car is mine" exists exactly while it is needed** — the countdown,
/// where identical silhouettes sit still on the grid — and each marker carries
/// what the drawing needs: the car's SCREEN position, the owning player's `up`
/// (so the number can face them), the seat number, and the color.
@MainActor
final class GridMarkerTests: XCTestCase {
    private func rig(players: Int) -> CouchRig {
        let rig = CouchRig(colorIndices: Array(0..<players))
        rig.layout(
            size: CGSize(width: 800, height: 1200),
            mapRect: CGRect(x: 0, y: 300, width: 800, height: 600))
        return rig
    }

    func testMarkersExistOnlyDuringTheCountdown() {
        var race = Race(
            track: TrackLibrary.track(id: "oval"), players: [PlayerID(0)],
            config: RaceConfig(laps: 3, countdownTicks: 120))
        let rig = rig(players: 1)
        let mapRect = CGRect(x: 0, y: 300, width: 800, height: 600)
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

    func testAMarkerFacesItsPlayerAndSitsOnItsCar() {
        let track = TrackLibrary.track(id: "oval")
        let race = Race(
            track: track, players: [PlayerID(0), PlayerID(1)],
            config: RaceConfig(laps: 3, countdownTicks: 120))
        // Face-to-face: player 1's zone is the top band, so their `up` points down.
        let rig = CouchRig(
            colorIndices: [0, 1], seating: SeatingConfig(faceToFace: true))
        let mapRect = CGRect(x: 0, y: 300, width: 800, height: 600)
        rig.layout(size: CGSize(width: 800, height: 1200), mapRect: mapRect)
        let markers = GridMarkers.markers(
            race: race, players: rig.players, mapRect: mapRect, palette: CouchGame.palette)
        XCTAssertEqual(markers.count, 2)
        XCTAssertEqual(markers[0].up, Vec2(0, -1))
        XCTAssertEqual(markers[1].up, Vec2(0, 1), "the far player's number faces the map")
        XCTAssertEqual(markers[0].number, 1)
        XCTAssertEqual(markers[1].number, 2)
        // Screen position = mapRect origin + world position * fitted scale.
        let scale = mapRect.width / track.size.x
        let expected = race.cars[0].state.position * scale + Vec2(mapRect.minX, mapRect.minY)
        XCTAssertEqual(markers[0].position.x, expected.x, accuracy: 1e-9)
        XCTAssertEqual(markers[0].position.y, expected.y, accuracy: 1e-9)
    }

    /// A networked guest drives global seats (say 2 and 3) — the marker numbers
    /// and cars must follow the SEAT, not the local band index.
    func testMarkersFollowGlobalSeatsOnAGuestDevice() {
        let race = Race(
            track: TrackLibrary.track(id: "oval"),
            players: [PlayerID(0), PlayerID(1), PlayerID(2), PlayerID(3)],
            config: RaceConfig(laps: 3, countdownTicks: 120))
        let rig = CouchRig(colorIndices: [2, 3], seats: [PlayerID(2), PlayerID(3)])
        let mapRect = CGRect(x: 0, y: 300, width: 800, height: 600)
        rig.layout(size: CGSize(width: 800, height: 1200), mapRect: mapRect)
        let markers = GridMarkers.markers(
            race: race, players: rig.players, mapRect: mapRect, palette: CouchGame.palette)
        XCTAssertEqual(markers.map(\.number), [3, 4], "a guest's markers must name its own seats")
    }
}
