import CoreGraphics
import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// The couch layout redesign: the map fits letterboxed, and control zones
/// are bands in the grass beside it (never over the track), each on its
/// player's near side.
@MainActor
final class CouchLayoutTests: XCTestCase {
    private let trackSize = Vec2(1600, 1000)  // the shipped 1.6:1 aspect

    // MARK: - fittedMapRect

    func testFittedMapRectPortraitIsWidthBoundAndCentred() {
        let screen = CGSize(width: 393, height: 852)
        let map = TrackRenderer.fittedMapRect(trackSize: trackSize, in: screen)
        XCTAssertEqual(map.width, 393, accuracy: 0.5)  // full width (width-bound)
        XCTAssertEqual(map.height, 1000 * 393 / 1600, accuracy: 0.5)  // ≈ 245.6
        XCTAssertEqual(map.midX, 393 / 2, accuracy: 1e-6)
        XCTAssertEqual(map.midY, 852 / 2, accuracy: 1e-6)  // centred → gaps top/bottom
        XCTAssertGreaterThan(map.minY, 250)  // a big top gap for a band
        XCTAssertGreaterThan(screen.height - map.maxY, 250)  // and bottom
    }

    func testFittedMapRectLandscapeReservesSideBands() {
        // Landscape (wide usable area) → bands go on the sides, so the map
        // fits within the width minus 2×minBand, not the full width.
        let screen = CGSize(width: 852, height: 393)
        let map = TrackRenderer.fittedMapRect(trackSize: trackSize, in: screen)
        XCTAssertLessThanOrEqual(map.width, 852 - 2 * 150 + 0.5)  // side bands reserved
        XCTAssertEqual(map.midX, 852 / 2, accuracy: 1e-6)  // centred
    }

    func testMinBandIsReservedAndMapAspectCapped() {
        // Portrait: the map never eats the reserved band minimum, and it
        // keeps its aspect (never stretched to fill the leftover).
        let screen = CGSize(width: 393, height: 852)
        let map = TrackRenderer.fittedMapRect(trackSize: trackSize, in: screen, minBand: 150)
        XCTAssertGreaterThanOrEqual(map.minY, 150 - 0.5)  // top band ≥ min
        XCTAssertGreaterThanOrEqual(screen.height - map.maxY, 150 - 0.5)  // bottom ≥ min
        XCTAssertEqual(map.width / map.height, 1.6, accuracy: 1e-6)  // aspect kept
    }

    func testSafeInsetsCarveOutTheNotch() {
        // With a top notch inset, the usable area starts below it, so the
        // top band (and thus the map) never rides under the notch.
        let screen = CGSize(width: 393, height: 852)
        let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let map = TrackRenderer.fittedMapRect(trackSize: trackSize, in: screen, safeInsets: insets)
        // Top band sits below the notch: map top ≥ notch + minBand.
        XCTAssertGreaterThanOrEqual(map.minY, 59 + 150 - 0.5)
    }

    // MARK: - band layout

    private func rig(_ n: Int, seating: SeatingConfig = SeatingConfig()) -> CouchRig {
        CouchRig(colorIndices: Array(0..<n), seating: seating)
    }

    private let screen = CGSize(width: 393, height: 852)
    private var map: CGRect {
        TrackRenderer.fittedMapRect(trackSize: trackSize, in: screen)
    }

    private func zones(_ rig: CouchRig) -> [CGRect] {
        rig.layout(size: screen, mapRect: map)
        return rig.players.map(\.zone)
    }

    func testEveryBandClearsTheMapAndFitsAStick() {
        for n in 1...4 {
            for zone in zones(rig(n)) {
                XCTAssertFalse(zone.intersects(map.insetBy(dx: 0, dy: 1)), "\(n)P band over map")
                XCTAssertGreaterThanOrEqual(zone.height, 132, "\(n)P band too short for a stick")
            }
        }
    }

    func testBandsFillTheGapFlushToTheMap() {
        // Bands stretch the whole gap (screen edge → map edge), no wasted
        // space — a band touches either the screen edge and the map edge.
        for zone in zones(rig(4)) {
            let flush =
                (abs(zone.minY) < 0.5 && abs(zone.maxY - map.minY) < 0.5)  // top band
                || (abs(zone.maxY - screen.height) < 0.5 && abs(zone.minY - map.maxY) < 0.5)
            XCTAssertTrue(flush, "band \(zone) doesn't fill its gap flush to the map")
        }
    }

    func testOnePlayerBandBelowMap() {
        let zone = zones(rig(1))[0]
        XCTAssertGreaterThanOrEqual(zone.minY, map.maxY - 0.5)  // below the map
        XCTAssertEqual(zone.width, screen.width, accuracy: 0.5)  // full width
    }

    func testTwoSideBySideSplitsBottomLeftRight() {
        let z = zones(rig(2))  // default = side-by-side
        // Both below the map, one left half, one right half.
        for zone in z { XCTAssertGreaterThanOrEqual(zone.minY, map.maxY - 0.5) }
        XCTAssertEqual(z[0].minX, 0, accuracy: 0.5)
        XCTAssertEqual(z[1].minX, screen.width / 2, accuracy: 0.5)
    }

    func testFaceToFacePutsFarPlayerBandAboveMap() {
        let z = zones(rig(2, seating: SeatingConfig(faceToFace: true)))
        // P0 near (below map), P1 far (above map).
        XCTAssertGreaterThanOrEqual(z[0].minY, map.maxY - 0.5)
        XCTAssertLessThanOrEqual(z[1].maxY, map.minY + 0.5)
    }

    func testFourPlayerUsesBothGapsSplitLeftRight() {
        let z = zones(rig(4))  // ZoneCorner order: bl, br, tl, tr
        // bottom-left, bottom-right below the map; top-left, top-right above.
        XCTAssertGreaterThanOrEqual(z[0].minY, map.maxY - 0.5)  // bottomLeft
        XCTAssertGreaterThanOrEqual(z[1].minY, map.maxY - 0.5)  // bottomRight
        XCTAssertLessThanOrEqual(z[2].maxY, map.minY + 0.5)  // topLeft
        XCTAssertLessThanOrEqual(z[3].maxY, map.minY + 0.5)  // topRight
        XCTAssertEqual(z[0].minX, 0, accuracy: 0.5)  // left half
        XCTAssertEqual(z[1].minX, screen.width / 2, accuracy: 0.5)  // right half
    }

    func testFarPlayersFaceAcrossTheTable() {
        // Top-row bands rotate (up.y > 0) so their controls face the player
        // sitting across the table.
        rig(4).layout(size: screen, mapRect: map)
        let r = rig(4)
        r.layout(size: screen, mapRect: map)
        XCTAssertEqual(r.players[0].up, Vec2(0, -1))  // bottom near
        XCTAssertEqual(r.players[2].up, Vec2(0, 1))  // top far, flipped
    }

    // MARK: - touch routing

    func testTouchOnMapAreaIsDropped() {
        let r = rig(2)
        r.layout(size: screen, mapRect: map)
        // A touch in the map's centre belongs to no band → ignored (no
        // owner), so a later move for it is a no-op. Fingers stay off track.
        r.touchBegan(id: 1, at: Vec2(map.midX, map.midY))
        // The player's stick never armed: no origin.
        XCTAssertNil(r.players[0].casual.origin)
        XCTAssertNil(r.players[1].casual.origin)
    }

    func testTouchInABandRoutesToThatPlayer() {
        let r = rig(2)
        r.layout(size: screen, mapRect: map)
        let leftBand = r.players[0].zone
        r.touchBegan(id: 1, at: Vec2(leftBand.midX, leftBand.midY))
        XCTAssertNotNil(r.players[0].casual.origin)
        XCTAssertNil(r.players[1].casual.origin)
    }
}
