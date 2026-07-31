import XCTest

@testable import SkidCore

/// Decals are **paint on a laid piece**, not pieces of their own: a sparse
/// `pieceIndex → decal` table in its own code section. So one arrow works for
/// every shape, present and future, without minting an id per geometry — and a
/// track with no decals encodes byte-for-byte as it did before they existed.
///
/// Being keyed by piece index makes them the fourth thing the mutation API has to
/// remap (with `gateSeams`, `fitters` and `pitches`).
final class DecalTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    private func ring() -> TrackLayout {
        TrackLayout(
            pieces: [
                Catalog.startGrid, Catalog.shortStraight, Catalog.curve45MediumLeft,
                Catalog.longStraight, Catalog.curve45MediumRight, Catalog.shortStraight,
            ],
            pitches: [.flat, .up, .up, .flat, .down, .down],
            gateSeams: [0, 2])
    }

    // MARK: - the model

    func testAPieceWithNoDecalHasNone() {
        let layout = ring()
        XCTAssertNil(layout.decal(at: 1))
        XCTAssertTrue(layout.decals.isEmpty)
    }

    func testADecalIsReadBackFromThePieceItWasPutOn() {
        var layout = ring()
        layout.decals[2] = .directionArrow
        XCTAssertEqual(layout.decal(at: 2), .directionArrow)
        XCTAssertNil(layout.decal(at: 1))
    }

    // MARK: - remapping (the reason this is the mutation API's business)

    /// Inserting shifts a decal along with its piece.
    func testInsertMovesDecalsWithTheirPieces() {
        var layout = ring()
        layout.decals = [1: .directionArrow, 4: .directionArrow]
        layout.insert(Catalog.shortStraight, at: 2)
        XCTAssertEqual(layout.decals.keys.sorted(), [1, 5], "decals did not follow their pieces")
    }

    /// Removing drops the victim's decal and pulls the rest back.
    func testRemoveDropsTheVictimsDecal() {
        var layout = ring()
        layout.decals = [2: .directionArrow, 4: .directionArrow]
        layout.remove(at: 2)
        XCTAssertEqual(layout.decals.keys.sorted(), [3], "the wrong decal survived")
    }

    /// Rotating a ring carries them too.
    func testRotateCarriesDecals() throws {
        var layout = try TrackCode.decode(
            "AQ4BGR8eAQ95AwMBHgEPAwMBHgEPAwMBHgEPAwMCAwAXIwMFBLAFoAAFAQI")
        let count = layout.pieces.count
        layout.decals = [3: .directionArrow]
        layout.rotate(to: 5)
        XCTAssertEqual(
            layout.decals.keys.sorted(), [(3 - 5 + count) % count],
            "a decal did not rotate with its piece")
    }

    /// The identity property, as for every other keyed field: a decal stays on the
    /// piece it was painted on, through any sequence of edits.
    func testDecalsStayOnTheirPieceThroughAnySequence() {
        var rng = SeededRNG(seed: 0xDECA1)
        for _ in 0..<200 {
            var layout = ring()
            let tag = 3
            layout.decals = [tag: .directionArrow]
            var tags = Array(0..<layout.pieces.count)

            for _ in 0..<8 {
                switch rng.next() % 3 {
                case 0:
                    let at = Int(rng.next() % UInt64(layout.pieces.count + 1))
                    layout.insert(Catalog.shortStraight, at: at)
                    tags.insert(-1, at: at)
                case 1 where layout.pieces.count > 1:
                    let at = Int(rng.next() % UInt64(layout.pieces.count))
                    layout.remove(at: at)
                    tags.remove(at: at)
                default:
                    guard layout.pieces.count > 1 else { continue }
                    let to = Int(rng.next() % UInt64(layout.pieces.count))
                    let before = layout.pieces
                    layout.rotate(to: to)
                    if layout.pieces != before { tags = Array(tags[to...] + tags[..<to]) }
                }

                for key in layout.decals.keys {
                    XCTAssertTrue(
                        layout.pieces.indices.contains(key), "decal key \(key) out of range")
                    XCTAssertEqual(tags[key], tag, "the decal drifted onto another piece")
                }
            }
        }
    }

    // MARK: - the code

    /// A track with no decals encodes exactly as it did before the section existed.
    func testTracksWithoutDecalsAreByteIdentical() throws {
        for builtin in TrackLibrary.builtins {
            let layout = try TrackCode.decode(builtin.code)
            XCTAssertTrue(layout.decals.isEmpty)
            XCTAssertEqual(
                TrackCode.encode(layout), builtin.code,
                "\(builtin.name) no longer round-trips to its own bytes")
        }
    }

    /// Decals round-trip, and cost bytes only when present.
    func testDecalsRoundTrip() throws {
        var layout = try TrackCode.decode(
            "AQ4BGR8eAQ95AwMBHgEPAwMBHgEPAwMBHgEPAwMCAwAXIwMFBLAFoAAFAQI")
        let bare = TrackCode.encode(layout)
        layout.decals = [1: .directionArrow, 7: .directionArrow]
        let coded = TrackCode.encode(layout)
        XCTAssertGreaterThan(coded.count, bare.count, "decals should cost bytes")

        let back = try TrackCode.decode(coded)
        XCTAssertEqual(back.decals, layout.decals)
        XCTAssertEqual(back.pieces, layout.pieces)
        XCTAssertEqual(TrackCode.encode(back), coded, "decals must be stable across a round-trip")
    }

    /// Normalization carries decals, so one track is still one code.
    func testNormalizingCarriesDecals() throws {
        let canonical = try TrackCode.decode(
            "AQ4BGR8eAQ95AwMBHgEPAwMBHgEPAwMBHgEPAwMCAwAXIwMFBLAFoAAFAQI")
        var respelled = canonical
        respelled.rotate(to: 4)
        respelled.decals = [2: .directionArrow]
        let expected = respelled.normalized().decals
        XCTAssertEqual(
            try TrackCode.decode(TrackCode.encode(respelled)).decals, expected,
            "a decal moved when the code was normalized")
    }

    /// A decal on a piece that no longer exists must not survive decoding — a
    /// hand-edited or truncated code should not paint a phantom piece.
    func testOutOfRangeDecalsAreDropped() throws {
        var layout = ring()
        layout.decals = [99: .directionArrow]
        let back = try TrackCode.decode(TrackCode.encode(layout))
        XCTAssertTrue(back.decals.isEmpty, "a decal outside the piece list was kept")
    }
}
