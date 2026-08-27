import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The map's paint reserve is per side, from geometry.** It used to be one
/// number on all four sides, sized as if the highest deck hugged every edge —
/// invisible under full-bleed grass, a navy frame around every elevated track
/// once grass stopped at the world.
@MainActor
final class DrawnOverhangTests: XCTestCase {
    /// A straight road across a 1000×600 world at a given height, hugging the
    /// LEFT edge only: its centerline sits half a road width in from x = 0 and
    /// far from every other edge.
    private func track(height: Double) -> Track {
        let half = Double(PieceCatalog.width) / 2
        let line = [Vec2(half, 300), Vec2(half, 200), Vec2(half, 400)]
        return Track(
            centerline: line, width: Double(PieceCatalog.width),
            heights: [height, height, height],
            startSlots: [Vec2(half, 300)], size: Vec2(1000, 600))
    }

    func testAFlatTrackPadsNothing() {
        let insets = TrackRenderer.drawnOverhang(track: track(height: 0), scale: 1)
        XCTAssertEqual(insets.leading, 0)
        XCTAssertEqual(insets.trailing, 0)
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.bottom, 0)
    }

    /// **Only the edge the raised road hugs is padded.** The right edge is 900
    /// units away and the top/bottom 200 — no deck widens or shadows that far.
    func testARaisedRoadAtOneEdgePadsThatEdgeAlone() {
        let insets = TrackRenderer.drawnOverhang(track: track(height: 2), scale: 1)
        XCTAssertGreaterThan(insets.leading, 0, "the hugged edge got no room")
        XCTAssertEqual(insets.trailing, 0, "the far edge was padded")
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.bottom, 0)
    }

    /// The hugged edge gets the old uniform formula's amount (which assumed
    /// exactly this: the highest deck at the edge), rounded up to a whole
    /// point — so the shrink is only where nothing overflowed.
    func testTheHuggedEdgeKeepsTheOldReserve() {
        let height = 2.0, scale = 1.5
        let insets = TrackRenderer.drawnOverhang(track: track(height: height), scale: scale)
        let widened = Double(PieceCatalog.width) / 2 * (Elevation.scale(atHeight: height) - 1)
        let old = (widened + Double(PieceCatalog.kerbBand)) * scale + 2
        XCTAssertGreaterThanOrEqual(Double(insets.leading), old - 1e-9)
        XCTAssertLessThan(Double(insets.leading), old + 1)
        XCTAssertEqual(insets.leading, insets.leading.rounded(), "not a whole point")
    }

    /// The per-side fit centres the map inside the box the padding leaves, so
    /// one padded side shifts the world by half that padding, not by all of it
    /// or none.
    func testTheFitCentresInsideThePaddedBox() {
        let pad = EdgeInsets(top: 0, leading: 40, bottom: 0, trailing: 0)
        let size = CGSize(width: 400, height: 900)
        let plain = TrackRenderer.fittedMapRect(trackSize: Vec2(1000, 600), in: size)
        let padded = TrackRenderer.fittedMapRect(
            trackSize: Vec2(1000, 600), in: size, screenPadding: pad)
        XCTAssertEqual(padded.minX, 40, accuracy: 1e-9, "the padded side is not clear")
        XCTAssertLessThan(padded.width, plain.width, "the map did not shrink to make room")
        XCTAssertEqual(padded.maxX, size.width, accuracy: 1e-9, "the unpadded side left a gap")
    }
}
