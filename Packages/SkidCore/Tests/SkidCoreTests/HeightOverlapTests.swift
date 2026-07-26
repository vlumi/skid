import XCTest

@testable import SkidCore

/// Height-aware overlap: what may cross what, decided by the same solidity
/// rule the runtime's walls use — road at height h is solid from `trunc(h)`
/// up to h. A ramp is a solid embankment down to the ground; a deck is thin
/// air below itself. The validator must agree with the sim, or a track can
/// validate and then be undrivable.
final class HeightOverlapTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    /// Start → up → deck → down, then a loop that comes back and crosses the
    /// descending ramp at `crossAt` extra shorts before turning in.
    private func rampCrossing(extraShorts: Int) -> TrackLayout {
        var pieces: [PieceID] = [
            Pieces.startGrid, Pieces.rampUp, Pieces.shortStraight, Pieces.shortStraight,
            Pieces.rampDown,
        ]
        pieces += [Pieces.curve45TightLeft, Pieces.curve45TightLeft]  // 90° left
        pieces += [Pieces.curve45TightLeft, Pieces.curve45TightLeft]  // heading back
        pieces += Array(repeating: Pieces.shortStraight, count: extraShorts)
        pieces += [Pieces.curve45TightLeft, Pieces.curve45TightLeft]  // turn in
        pieces += [Pieces.shortStraight]  // ...and across the ramp's line
        return TrackLayout(pieces: pieces, gateSeams: [0])
    }

    /// **Ground road may not cross a ramp's low half.** Both are physically at
    /// ground level there — the sim's embankment rails make it undrivable — so
    /// the validator must refuse it. It used to validate: the exemption
    /// compared whole-piece ENTRY heights, and a descending ramp enters at 1.
    func testGroundRoadAcrossARampLowHalfIsAnOverlap() {
        let layout = rampCrossing(extraShorts: 0)
        XCTAssertTrue(
            TrackValidator.validate(layout).problems.contains(.overlap),
            "crossing a ramp where it meets the ground is a real collision")
    }

    /// **Ground road may not cross a ramp's high half either.** There is road
    /// overhead, but a ramp is a solid embankment — the compiler seals its
    /// mouth with a cap wall — so unlike a deck there is no passage beneath.
    func testGroundRoadAcrossARampHighHalfIsAnOverlap() {
        let layout = rampCrossing(extraShorts: 1)
        XCTAssertTrue(
            TrackValidator.validate(layout).problems.contains(.overlap),
            "the space under a ramp is embankment, not passage")
    }

    /// **Ground road under a deck stays legal** — that is what a bridge is.
    /// The eight ships exactly this, so it is the positive control.
    func testGroundRoadUnderADeckStaysLegal() throws {
        let layout = try XCTUnwrap(TrackLibrary.layout(id: "eight"))
        XCTAssertFalse(TrackValidator.validate(layout).problems.contains(.overlap))
    }
}
