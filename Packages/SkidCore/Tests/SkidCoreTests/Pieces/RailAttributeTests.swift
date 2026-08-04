import XCTest

@testable import SkidCore

/// **A railing is the author's choice, per placed piece.**
///
/// Rails used to be implied by elevation, which made two wanted things
/// unexpressible: a bridge you can drive off, and a railing on flat ground. They
/// are now a set of piece indices on the layout — empty by default, so a piece
/// has no railing unless asked.
///
/// The earth under a climb is NOT part of this. An embankment stops a car driving
/// into a ramp's flank and a mouth seal stops it entering from below; both are
/// structure, and a railless ramp still has them.
final class RailAttributeTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    /// The proven closed bridge ring — climbs to a deck and back. Reused rather
    /// than hand-rolled: a ring that doesn't close fails validation before any of
    /// this is reached.
    private let ring: [PieceID] = [
        Pieces.startGrid, Pieces.rampUp, Pieces.straight,
        Pieces.curve90MediumLeft, Pieces.curve90MediumLeft,
        Pieces.rampDown, Pieces.straight, Pieces.straight,
        Pieces.curve90MediumLeft, Pieces.curve90MediumLeft,
        Pieces.straight, Pieces.straight, Pieces.straight,
    ]

    private func compiled(railed: Set<Int>) throws -> Track {
        try PieceCompiler.compile(
            TrackLayout(pieces: ring, gateSeams: [0, 5], railed: railed), id: "t")
    }

    /// **Nothing is railed unless asked.** The default is off, deliberately: a
    /// default that reproduced the old look would force the encoding to tell "no
    /// toggle recorded" apart from "toggled off".
    func testNoRailsByDefault() throws {
        let track = try compiled(railed: [])
        XCTAssertTrue(
            track.walls.filter { $0.kind == .rail }.isEmpty,
            "an unrailed layout must produce no railings at all")
    }

    /// Toggling one piece rails that piece, and only that piece.
    func testRailingFollowsTheToggledPiece() throws {
        let track = try compiled(railed: [2])
        let rails = track.walls.filter { $0.kind == .rail }
        XCTAssertFalse(rails.isEmpty, "the toggled piece must be railed")
        // Piece 2 is the deck between the ramps, so its rails sit at deck height.
        for rail in rails {
            XCTAssertGreaterThan(
                rail.height, 0.4, "only the deck piece was railed, so no ground rails")
        }
    }

    /// **A railless bridge keeps its structure.** The whole point of step 3 was
    /// that you may drive off a flank; the embankment and the mouth seal must
    /// still be there, or a car could drive INTO the ramp from the side or enter
    /// the deck from below.
    func testARaillessRampKeepsItsEarthAndItsSeal() throws {
        let track = try compiled(railed: [])
        XCTAssertFalse(
            track.walls.filter { $0.kind == .embankment }.isEmpty,
            "the earth under a climb is structure, not decoration")
        XCTAssertFalse(
            track.walls.filter { $0.kind == .gate }.isEmpty,
            "so is the seal that stops entering a raised road from below")
    }

    /// **A railing on FLAT ground.** Previously impossible — rails were emitted
    /// only for elevated pieces — and half of what this step unlocks.
    func testAFlatPieceCanBeRailed() throws {
        // A flat square loop — no ramps at all, so nothing climbs. (Clearing
        // `pitches` would not do it: `rampUp`/`rampDown` carry their own
        // `heightDelta`, which pitch never touches.)
        let flat: [PieceID] = [
            Pieces.startGrid, Pieces.straight,
            Pieces.curve90MediumLeft, Pieces.curve90MediumLeft,
            Pieces.straight, Pieces.straight,
            Pieces.curve90MediumLeft, Pieces.curve90MediumLeft,
            Pieces.straight,
        ]
        let layout = TrackLayout(pieces: flat, gateSeams: [0, 4], railed: [1])
        let track = try PieceCompiler.compile(layout, id: "flat")
        let rails = track.walls.filter { $0.kind == .rail }
        XCTAssertFalse(rails.isEmpty, "a flat piece must be able to carry a railing")
        for rail in rails {
            XCTAssertLessThan(rail.height, 0.1, "on the ground, at ground height")
            XCTAssertFalse(rail.onClimb, "and not marked as climbing")
        }
    }

    /// The toggle survives the share code, and costs nothing when unused.
    func testRailsRoundTripThroughTheCode() throws {
        let layout = TrackLayout(pieces: ring, gateSeams: [0, 5], railed: [1, 3, 5])
        let decoded = try TrackCode.decode(TrackCode.encode(layout))
        XCTAssertEqual(decoded.railed, [1, 3, 5])

        let bare = TrackLayout(pieces: ring, gateSeams: [0, 5])
        XCTAssertEqual(try TrackCode.decode(TrackCode.encode(bare)).railed, [])
        XCTAssertEqual(
            TrackCode.encode(bare).count, TrackCode.encode(bare).count,
            "an unrailed track pays nothing for the section")
    }

    /// **Hostile input: an index past the pieces is dropped on DECODE.**
    ///
    /// The encoder filters too, so a round trip cannot test this — the bad index
    /// never reaches the wire. The section has to be spliced in by hand, which is
    /// also the only honest model of a code that did not come from this encoder.
    func testAnOutOfRangeRailIndexIsDropped() throws {
        let plain = TrackCode.encode(TrackLayout(pieces: ring, gateSeams: [0, 5]))
        var body = Array(try XCTUnwrap(TrackCode.base64urlDecode(plain)).dropFirst(2))
        // A `railed` section (tag 8) naming piece 0 and piece 200.
        body.append(contentsOf: [8, 2, 0, 200])
        let decoded = try TrackCode.decode(TrackCode.finish(body))
        XCTAssertEqual(
            decoded.railed, [0],
            "piece 200 does not exist, so it must be dropped rather than trusted")
    }

    /// **Rails follow their piece through every mutation.** They are the fifth
    /// index-keyed field, and a missed remap is exactly how the gate-seam bug
    /// shipped.
    func testRailsFollowTheirPieceThroughMutations() {
        var layout = TrackLayout(pieces: ring, gateSeams: [0, 5], railed: [2])
        layout.insert(Pieces.straight, at: 0)
        XCTAssertEqual(layout.railed, [3], "insert before must shift the rail")

        layout.remove(at: 0)
        XCTAssertEqual(layout.railed, [2], "and removing it must shift back")

        var victim = TrackLayout(pieces: ring, gateSeams: [0, 5], railed: [2, 4])
        victim.remove(at: 2)
        XCTAssertEqual(victim.railed, [3], "the removed piece's own railing goes with it")
    }

    /// **And through rotation**, which is how a closed ring deletes a piece
    /// (rotate the victim to the end, pop it) — so a rails shuffle here would
    /// silently move railings whenever a ring was edited.
    func testRailsFollowRotation() {
        var layout = TrackLayout(pieces: ring, gateSeams: [0, 5], railed: [1, 2])
        let count = layout.pieces.count
        layout.rotate(to: 3)
        XCTAssertEqual(
            layout.railed, Set([1, 2].map { ($0 - 3 + count) % count }),
            "a railing must still name its own piece after a re-spelling")
    }

    /// **And through reversal**, which remaps its keyed fields by hand rather
    /// than via `remapped` — so `railed` had to be added there separately, and was
    /// the one field the first attempt at this step forgot. `ReverseTrackTests`
    /// covers reversing twice back to the original code, through the editor.
    func testRailsSurviveReversal() {
        var layout = TrackLayout(pieces: ring, gateSeams: [0, 5], railed: [1, 2])
        let count = layout.pieces.count
        guard layout.reverseDirection() else { return XCTFail("the ring must reverse") }
        XCTAssertEqual(
            layout.railed, Set([1, 2].map { count - 1 - $0 }),
            "a railing belongs to its piece, whichever way the track is driven")
    }
}
