import XCTest

@testable import SkidCore

/// The world has storeys, and validation — not the palette — is what keeps
/// road inside them. The editor's single ramp button used to auto-pick a legal
/// direction, which made this nobody's rule: climbing past the deck and
/// digging below the ground both validated. With pitch coming to ordinary
/// pieces, every button can climb, so the bound must live here.
final class HeightBoundsTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    func testClimbingPastTheTopLevelIsRefused() {
        let onDeck = TrackLayout(pieces: [Pieces.startGrid, Pieces.rampUp], gateSeams: [0])
        XCTAssertFalse(
            TrackValidator.canAppend(Pieces.rampUp, to: onDeck),
            "a second climb would reach a storey that doesn't exist")
        var stacked = onDeck
        stacked.pieces.append(Pieces.rampUp)
        XCTAssertTrue(
            TrackValidator.validate(stacked).problems.contains { problem in
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
