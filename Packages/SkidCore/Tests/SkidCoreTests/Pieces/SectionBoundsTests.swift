import XCTest

@testable import SkidCore

/// **A TLV length is one byte**, so a section payload over 255 wraps and
/// desynchronizes the parser — `encode` emits a code its own `decode` rejects,
/// with nothing thrown at the encode site.
///
/// Reachable, not theoretical: decals are 2 bytes each and `maxLength` caps a
/// layout at 127 primitives, so a fully decorated track lands at 254 payload
/// bytes — one byte under. Raising that cap, or any future wider entry, walks
/// straight off the cliff (measured: 131 decals wrote a length of 6 and the
/// code no longer decoded).
final class SectionBoundsTests: XCTestCase {
    /// The most decals a layout can carry today still fits, with 1 byte spare.
    func testAFullyDecoratedTrackStillFits() throws {
        let layout = decorated(pieces: 127)
        XCTAssertEqual(TrackCode.sectionPayloadSize(decals: layout.decals.count), 254)

        let code = TrackCode.encode(layout)
        let back = try TrackCode.decode(code)
        XCTAssertEqual(back.decals.count, 127)
    }

    /// The margin is one byte, and that is the whole reason the guard exists.
    func testTheDecalSectionIsOneByteFromTheCeiling() {
        XCTAssertEqual(TrackCode.maxSectionPayload - 254, 1)
    }

    /// `encodedSize` agrees with the string it describes, for every built-in.
    func testEncodedSizeMatchesTheCode() throws {
        for builtin in TrackLibrary.builtins {
            let layout = try TrackCode.decode(builtin.code)
            XCTAssertEqual(
                TrackCode.encodedSize(layout), TrackCode.encode(layout).count,
                "size disagreed for \(builtin.id)")
        }
    }

    /// The measured sizes, pinned. Not a change detector for its own sake:
    /// signing adds a known +100 bytes, and these are what that is measured
    /// against — so silent format growth should turn the build red.
    func testBuiltinCodeSizesArePinned() throws {
        let sizes = try TrackLibrary.builtins.map { builtin -> Int in
            TrackCode.encodedSize(try TrackCode.decode(builtin.code))
        }
        // The two flat tracks are unchanged; the eight (36→50) and clover (59→92)
        // carry a `railed` section now — one byte per railed piece, plus the
        // 2-byte TLV header. A flat track still pays nothing for railings it
        // does not have.
        XCTAssertEqual(sizes, [32, 32, 50, 92])
    }

    private func decorated(pieces count: Int) -> TrackLayout {
        let pieces =
            [PieceCatalog.startPieceID]
            + Array(repeating: PieceCatalog.ID.shortStraight, count: count - 1)
        var decals: [Int: Decal] = [:]
        for index in 0..<count { decals[index] = .directionArrow }
        return TrackLayout(pieces: pieces, gateSeams: [0], decals: decals)
    }
}
