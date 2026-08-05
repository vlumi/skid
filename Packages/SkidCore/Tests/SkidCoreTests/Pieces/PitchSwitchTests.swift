import XCTest

@testable import SkidCore

/// The mode-switch bytes: how a lone half-climb — a pitched primitive no
/// compound absorbs — reaches the share code. A switch id sets the pitch for
/// every bare primitive after it; compounds carry their own explicit pitches
/// and never touch the state.
final class PitchSwitchTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    /// A single pitched short survives the round trip — the case that used to
    /// trip the packing precondition, because it had no byte form at all.
    func testALoneHalfClimbRoundTrips() throws {
        let layout = TrackLayout(
            pieces: [Pieces.startGrid, Pieces.shortStraight, Pieces.shortStraight],
            pitches: [.flat, .up, .flat], gateSeams: [0, 1])
        let back = try TrackCode.decode(TrackCode.encode(layout))
        XCTAssertEqual(back, layout.normalized())
    }

    /// Three same-pitch shorts: the compound eats two, the switch carries the
    /// third — and the decode reassembles all three at the right pitch.
    func testCompoundsAndSwitchesCompose() throws {
        let layout = TrackLayout(
            pieces: [Pieces.startGrid] + Array(repeating: Pieces.shortStraight, count: 3),
            pitches: [.flat, .up, .up, .up], gateSeams: [0, 2])
        let back = try TrackCode.decode(TrackCode.encode(layout))
        XCTAssertEqual(back, layout.normalized())
    }

    /// Pitched 45° corners — climbing road that bends — round-trip too.
    func testPitchedCornersRoundTrip() throws {
        let layout = TrackLayout(
            pieces: [
                Pieces.startGrid, Pieces.curve45MediumLeft, Pieces.curve45MediumLeft,
                Pieces.shortStraight,
            ],
            pitches: [.flat, .up, .down, .flat], gateSeams: [0, 2])
        let back = try TrackCode.decode(TrackCode.encode(layout))
        XCTAssertEqual(back, layout.normalized())
    }

    /// Canonical: decode → re-encode is byte identity, switches included.
    func testSwitchEncodingIsAFixedPoint() throws {
        let layout = TrackLayout(
            pieces: [Pieces.startGrid, Pieces.shortStraight, Pieces.curve45TightRight],
            pitches: [.flat, .up, .up], gateSeams: [0, 1])
        let code = TrackCode.encode(layout)
        XCTAssertEqual(TrackCode.encode(try TrackCode.decode(code)), code)
    }

    /// A full climb still costs its one compound byte: no switches appear when
    /// the ramp packs — so every pre-lattice code keeps its exact bytes.
    func testFullClimbsStillPackWithoutSwitches() throws {
        let layout = TrackLayout(
            pieces: [Pieces.startGrid, Pieces.shortStraight, Pieces.shortStraight],
            pitches: [.flat, .up, .up], gateSeams: [0])
        let code = TrackCode.encode(layout)
        let back = try TrackCode.decode(code)
        XCTAssertEqual(back, layout.normalized())
        // Same track spelled through the ramp compound: identical bytes.
        let viaCompound = TrackLayout(
            pieces: [Pieces.startGrid] + PieceExpansion.expand(Pieces.rampUp).map(\.id),
            pitches: [.flat] + PieceExpansion.expand(Pieces.rampUp).map(\.pitch),
            gateSeams: [0])
        XCTAssertEqual(TrackCode.encode(viaCompound), code)
    }

    /// The switch block is reserved: no catalog piece may ever take those ids,
    /// or a shape would read as a mode change.
    func testTheSwitchBlockIsReserved() {
        for id in 112...127 {
            XCTAssertNil(
                PieceCatalog.piece(id),
                "catalog id \(id) collides with the mode-switch block")
        }
    }

    /// Placing under a pitch mode goes through the same validation as anything
    /// else: descending from the ground is refused, climbing is allowed, and a
    /// second half-climb continues from the first.
    func testPitchedPlacementValidates() {
        let ground = TrackLayout(pieces: [Pieces.startGrid], gateSeams: [0])
        XCTAssertFalse(TrackValidator.canAppend(Pieces.shortStraight, pitch: .down, to: ground))
        XCTAssertTrue(TrackValidator.canAppend(Pieces.shortStraight, pitch: .up, to: ground))
        var half = ground
        half.append(contentsOf: PieceExpansion.expand(Pieces.shortStraight, mode: .up))
        XCTAssertTrue(TrackValidator.canAppend(Pieces.shortStraight, pitch: .up, to: half))
        XCTAssertTrue(TrackValidator.canAppend(Pieces.shortStraight, pitch: .down, to: half))
        // And from the TOP storey, up is out of the world. Pitch climbs half a
        // level, so it takes two pitched pieces per storey to get there.
        var ceiling = ground
        for _ in 0..<(Track.highestLevel * 2) {
            ceiling.append(contentsOf: PieceExpansion.expand(Pieces.shortStraight, mode: .up))
        }
        XCTAssertFalse(
            TrackValidator.canAppend(Pieces.shortStraight, pitch: .up, to: ceiling),
            "climbing past the top storey must be refused, wherever the top is")
    }
}
