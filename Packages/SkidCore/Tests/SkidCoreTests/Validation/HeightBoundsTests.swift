import XCTest

@testable import SkidCore

/// The world has storeys, and validation — not the palette — is what keeps
/// road inside them. The editor's single ramp button used to auto-pick a legal
/// direction, which made this nobody's rule: climbing past the deck and
/// digging below the ground both validated. With pitch coming to ordinary
/// pieces, every button can climb, so the bound must live here.
final class HeightBoundsTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    /// Derived from `Track.highestLevel` rather than pinning "one deck": the point
    /// is that the world HAS a ceiling and climbing through it is refused, which
    /// must hold at whatever height that ceiling sits.
    func testClimbingPastTheTopLevelIsRefused() {
        // `rampUp` climbs a whole level, so stack exactly enough to reach the top.
        var atCeiling = TrackLayout(
            pieces: [Pieces.startGrid]
                + Array(repeating: Pieces.rampUp, count: Track.highestLevel),
            gateSeams: [0])
        XCTAssertFalse(
            TrackValidator.validate(atCeiling).problems.contains { problem in
                if case .heightOutOfBounds = problem { return true }
                return false
            }, "climbing exactly to the top storey is legal")
        XCTAssertFalse(
            TrackValidator.canAppend(Pieces.rampUp, to: atCeiling),
            "one more climb would reach a storey that doesn't exist")
        atCeiling.pieces.append(Pieces.rampUp)
        XCTAssertTrue(
            TrackValidator.validate(atCeiling).problems.contains { problem in
                if case .heightOutOfBounds = problem { return true }
                return false
            })
    }

    func testDiggingBelowTheGroundIsRefused() {
        let ground = TrackLayout(pieces: [Pieces.startGrid], gateSeams: [0])
        XCTAssertFalse(
            TrackValidator.canAppend(Pieces.rampDown, to: ground),
            "descending from the ground digs below the world — tunnels aren't in yet")
    }

    /// The rule must not catch anything legal: a climb to the deck, riding it,
    /// and coming back down is the whole point of ramps.
    func testAnOrdinaryBridgeStaysLegal() {
        let bridge = TrackLayout(
            pieces: [
                Pieces.startGrid, Pieces.rampUp, Pieces.shortStraight, Pieces.rampDown,
            ], gateSeams: [0])
        XCTAssertFalse(
            TrackValidator.validate(bridge).problems.contains { problem in
                if case .heightOutOfBounds = problem { return true }
                return false
            })
        XCTAssertTrue(TrackValidator.canAppend(Pieces.shortStraight, to: bridge))
    }
}
