import XCTest

@testable import SkidCore

/// A climb's height profile is one S-curve regardless of how many pieces carry
/// it. Splitting the full ramp into halves briefly terraced it — each half
/// eased to a standstill at the apex — because easing was piece-local. The walk
/// now sets each end from the sequence: ease against flat road, run straight
/// through into a continuing climb.
final class ClimbProfileTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    private func climbHalves() throws -> (first: PlacedPiece, second: PlacedPiece) {
        let layout = TrackLayout(
            pieces: [Pieces.startGrid, Pieces.shortStraight, Pieces.shortStraight],
            pitches: [.flat, .up, .up], gateSeams: [0])
        let placed = layout.walk().placed
        return (placed[1], placed[2])
    }

    /// No shelf at the apex: the seam-facing ends run at the climb's own slope,
    /// so the junction is as steep as the middle of the old single ramp — not
    /// flat, which is what "eased at every piece end" produced.
    func testASplitClimbHasNoShelfAtTheApex() throws {
        let (first, second) = try climbHalves()
        XCTAssertEqual(first.exitHeight, 0.5, accuracy: 1e-9)
        XCTAssertEqual(second.exitHeight, 1.0, accuracy: 1e-9)
        // Slope just before and just after the apex, per unit of fraction.
        let before = (first.height(atFraction: 1.0) - first.height(atFraction: 0.99)) / 0.01
        let after = (second.height(atFraction: 0.01) - second.height(atFraction: 0.0)) / 0.01
        XCTAssertEqual(before, after, accuracy: 0.02, "the apex must be slope-continuous")
        XCTAssertGreaterThan(before, 0.4, "the apex must not flatten into a shelf")
    }

    /// The outer ends still ease: ground and deck are met smoothly, exactly as
    /// the single-piece ramp always did.
    func testTheOuterEndsStillEase() throws {
        let (first, second) = try climbHalves()
        let atGround = (first.height(atFraction: 0.01) - first.height(atFraction: 0)) / 0.01
        let atDeck = (second.height(atFraction: 1.0) - second.height(atFraction: 0.99)) / 0.01
        XCTAssertLessThan(abs(atGround), 0.03, "the climb must ease off the ground")
        XCTAssertLessThan(abs(atDeck), 0.03, "the climb must ease onto the deck")
    }

    /// An isolated climb keeps the classic smoothstep — both ends eased.
    func testAnIsolatedClimbIsUnchanged() throws {
        let layout = TrackLayout(
            pieces: [Pieces.startGrid, Pieces.shortStraight, Pieces.shortStraight],
            pitches: [.flat, .up, .flat], gateSeams: [0])
        let lone = layout.walk().placed[1]
        XCTAssertEqual(lone.height(atFraction: 0.5), 0.25, accuracy: 1e-9)
        let start = (lone.height(atFraction: 0.01) - lone.height(atFraction: 0)) / 0.01
        let end = (lone.height(atFraction: 1.0) - lone.height(atFraction: 0.99)) / 0.01
        XCTAssertLessThan(abs(start), 0.03)
        XCTAssertLessThan(abs(end), 0.03)
    }
}
