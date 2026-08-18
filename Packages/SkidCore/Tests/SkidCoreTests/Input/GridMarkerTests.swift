import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **"Which car is mine" exists exactly while it is needed** — the countdown,
/// where identical silhouettes sit still on the grid — and each marker carries
/// what the drawing needs: the car's SCREEN position, its tail's spot on the
/// shared base line, and the color.
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

    /// Each marker sits on its own car.
    func testMarkersSitOnTheirCars() {
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
    }

    /// **The arrows come in from the roomiest map edge**, so a grid parked against
    /// an edge keeps every arrow over the map — the reported constraint.
    func testArrowsApproachFromTheRoomiestSide() {
        let map = CGRect(x: 0, y: 0, width: 800, height: 800)
        // A grid hugging the TOP edge: the arrows must come from below, pointing up.
        XCTAssertEqual(
            GridMarkers.roomiestApproach(
                grid: CGRect(x: 300, y: 10, width: 200, height: 40), mapRect: map),
            Vec2(0, -1))
        // Hugging the RIGHT edge: in from the left, pointing right.
        XCTAssertEqual(
            GridMarkers.roomiestApproach(
                grid: CGRect(x: 700, y: 300, width: 60, height: 200), mapRect: map),
            Vec2(1, 0))
    }

    /// **The tails spread along one base line, one arrow-width apart** — four
    /// arrows aimed straight at a two-by-two grid landed on top of each other
    /// (reported from device). Order follows the cars, so no arrow crosses
    /// another's.
    func testTailsSpreadAlongOneBaseLineWithoutOverlap() {
        // A tight two-by-two grid, approached from below.
        let positions = [Vec2(400, 400), Vec2(412, 400), Vec2(400, 384), Vec2(412, 384)]
        let anchors = GridMarkers.spreadAnchors(positions: positions, direction: Vec2(0, -1))
        for anchor in anchors {
            XCTAssertEqual(
                anchor.y, 400 + GridMarkers.anchorSetback, accuracy: 1e-9,
                "every tail sits on the one base line behind the rearmost car")
        }
        let xs = anchors.map(\.x).sorted()
        for (near, far) in zip(xs, xs.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                far - near, GridMarkers.anchorSpacing - 1e-9, "two tails overlap")
        }
        // Order preserved: the left car keeps the left tail.
        XCTAssertLessThan(anchors[0].x, anchors[1].x)
        XCTAssertLessThan(anchors[2].x, anchors[3].x)
    }

    /// A networked guest drives global seats (say 2 and 3) — the markers must
    /// follow the SEAT's cars, not the local band index's.
    func testMarkersFollowGlobalSeatsOnAGuestDevice() {
        let race = race(players: 4)
        let rig = rig(colorIndices: [2, 3], seats: [PlayerID(2), PlayerID(3)])
        let markers = GridMarkers.markers(
            race: race, players: rig.players, mapRect: mapRect, palette: CouchGame.palette)
        let scale = mapRect.width / race.track.size.x
        let expected = [2, 3].map { seat in
            race.cars.first { $0.id == PlayerID(seat) }!.state.position * scale
                + Vec2(mapRect.minX, mapRect.minY)
        }
        XCTAssertEqual(markers.count, 2)
        for (marker, position) in zip(markers, expected) {
            XCTAssertEqual(
                marker.position.x, position.x, accuracy: 1e-9,
                "a guest's marker must sit on its own seat's car")
            XCTAssertEqual(marker.position.y, position.y, accuracy: 1e-9)
        }
    }
}
