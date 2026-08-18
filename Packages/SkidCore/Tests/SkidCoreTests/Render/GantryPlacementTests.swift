import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The start gantry must not park on the grid.** It sits at the screen center —
/// which is exactly where a track like the eight puts its start line, so the lights
/// landed on the cars and their ownership arrows (reported from device). When the
/// panel would overlap the grid, it dodges vertically into the roomier gap, staying
/// over the map.
final class GantryPlacementTests: XCTestCase {
    private let screen = CGSize(width: 750, height: 1334)

    private func panel(at center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - StartLights.panelSize.width / 2,
            y: center.y - StartLights.panelSize.height / 2,
            width: StartLights.panelSize.width, height: StartLights.panelSize.height)
    }

    private func gridBox(race: Race, mapRect: CGRect) -> CGRect {
        let scale = mapRect.width / race.track.size.x
        let points = race.cars.map { car in
            CGPoint(
                x: mapRect.minX + car.state.position.x * scale,
                y: mapRect.minY + car.state.position.y * scale)
        }
        var box = CGRect(origin: points[0], size: .zero)
        for point in points.dropFirst() {
            box = box.union(CGRect(origin: point, size: .zero))
        }
        return box.insetBy(dx: -StartLights.gridClearance, dy: -StartLights.gridClearance)
    }

    /// The eight's start line is mid-map: the reported case. The panel must clear
    /// the grid and stay over the map.
    func testTheGantryDodgesAMidMapGrid() {
        let track = TrackLibrary.track(id: "eight")
        let race = Race(
            track: track, players: (0..<4).map(PlayerID.init),
            config: RaceConfig(laps: 3, countdownTicks: 120))
        let mapRect = TrackRenderer.fittedMapRect(trackSize: track.size, in: screen)
        let center = StartLights.gantryCenter(race: race, mapRect: mapRect, size: screen)
        XCTAssertNotEqual(
            center, CGPoint(x: screen.width / 2, y: screen.height / 2),
            "the eight's grid is at the screen center; the gantry must move")
        XCTAssertFalse(
            panel(at: center).intersects(gridBox(race: race, mapRect: mapRect)),
            "the gantry still covers the grid")
        XCTAssertGreaterThanOrEqual(panel(at: center).minY, mapRect.minY)
        XCTAssertLessThanOrEqual(panel(at: center).maxY, mapRect.maxY)
    }

    /// With the grid away from the screen center, the gantry stays exactly there —
    /// the dodge is an exception, not a relayout.
    func testTheGantryStaysCenteredWhenTheGridIsClear() {
        let track = TrackLibrary.track(id: "eight")
        let race = Race(
            track: track, players: (0..<4).map(PlayerID.init),
            config: RaceConfig(laps: 3, countdownTicks: 120))
        // A tall screen with the map at the top: the screen center is far below
        // every grid slot.
        let tall = CGSize(width: 750, height: 4000)
        let mapRect = CGRect(x: 0, y: 0, width: 750, height: 750)
        let center = StartLights.gantryCenter(race: race, mapRect: mapRect, size: tall)
        XCTAssertEqual(center, CGPoint(x: tall.width / 2, y: tall.height / 2))
    }
}
