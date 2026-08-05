import XCTest

@testable import SkidCore

/// **Anything drawn across the road must use the road's DRAWN width.**
///
/// `Elevation.scale` widens a road as it rises, and a flat `width / 2` has now been
/// wrong in eight separate places — the rail band, the gate span, the grip width, the
/// tap reach, the selection wash, the checkered start line, the construction strips
/// and the gate-seam candidate. Each was found on device, one at a time.
///
/// This pins the ARITHMETIC that every one of them needs, so the next site to get it
/// wrong is a failing test rather than a screenshot.
final class DrawnWidthTests: XCTestCase {
    /// The scale is linear in height and never shrinks — the property every caller
    /// relies on when it multiplies a nominal width by it.
    func testTheScaleGrowsWithHeight() {
        var previous = 0.0
        for storey in 0...Track.highestLevel {
            let scale = Elevation.scale(atHeight: Double(storey))
            XCTAssertGreaterThan(scale, previous, "storey \(storey) must be wider than below")
            previous = scale
        }
        XCTAssertEqual(Elevation.scale(atHeight: 0), 1, accuracy: 1e-9, "ground is nominal")
    }

    /// **The gap a flat width leaves.** 12 units per storey on a 120-unit road — small
    /// at the deck, which is why this went unnoticed for so long, and 36 units at
    /// height 3, where it reads as a barrier in the wrong place.
    func testTheGapAFlatWidthLeaves() {
        let nominal = Double(PieceCatalog.width) / 2
        for storey in 1...Track.highestLevel {
            let drawn = nominal * Elevation.scale(atHeight: Double(storey))
            XCTAssertEqual(
                drawn - nominal, 12 * Double(storey), accuracy: 0.001,
                "a flat half-width is \(12 * storey) units short at storey \(storey)")
        }
    }

    /// **`halfWidth` is the one definition**, and it agrees with the scale — so a
    /// caller that asks the track rather than doing its own arithmetic cannot drift.
    func testHalfWidthIsTheScaledWidth() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.towerOfBabel), id: "t")
        for storey in 0...Track.highestLevel {
            let height = Double(storey)
            XCTAssertEqual(
                track.halfWidth(atHeight: height),
                track.width / 2 * Elevation.scale(atHeight: height),
                accuracy: 1e-9,
                "halfWidth must BE the scaled width, not a second opinion")
        }
    }

    /// And the footprint reaches further still, by the kerb band — the extent anything
    /// covering the road (the under-deck window) has to use.
    func testTheFootprintReachesPastTheAsphalt() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.towerOfBabel), id: "t")
        for storey in 0...Track.highestLevel {
            let height = Double(storey)
            XCTAssertGreaterThan(
                track.footprintHalfWidth(atHeight: height),
                track.halfWidth(atHeight: height),
                "the rails stand outboard of the asphalt, so the footprint is wider")
        }
    }
}
