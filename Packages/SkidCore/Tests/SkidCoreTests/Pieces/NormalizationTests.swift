import XCTest

@testable import SkidCore

/// **One track, one code.** A closed ring can be written starting from any of its
/// pieces, and all of those spellings are the same track — so encoding rotates
/// the list to a canonical anchor first. Without that, share codes stop being
/// identities: the same track saved twice, built differently, would not match.
///
/// The anchor is the start line (and, once it exists, the fitting piece — which
/// must be first because the walk grows both chains outward from it; see
/// docs/flexible-tracks-plan.md).
final class NormalizationTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    private let compact: [PieceID] = [
        Catalog.startGrid, Catalog.curve90MediumRight, Catalog.curve90MediumRight,
        Catalog.curve90MediumRight, Catalog.curve90TightLeft, Catalog.shortStraight,
        Catalog.shortStraight, Catalog.curve90TightRight, Catalog.curve90MediumRight,
        Catalog.jog240Right,
    ]

    /// The ring as PRIMITIVES — what a code decodes to and what the editor
    /// works in. Seams index primitives, so a compound spelling and its
    /// expansion are different layouts with the same shape; rotating has to be
    /// tested in the form that round-trips.
    private func primitiveRing() throws -> TrackLayout {
        try TrackCode.decode(
            TrackCode.encode(TrackLayout(pieces: compact, gateSeams: [0, 3, 6])))
    }

    /// A ring rotated to start anywhere encodes to the same bytes.
    func testRotatingTheRingDoesNotChangeItsCode() throws {
        let seed = try primitiveRing()
        let count = seed.pieces.count
        var codes: Set<String> = []
        for offset in 0..<count {
            var rotated = seed
            rotated.pieces = Array(seed.pieces[offset...] + seed.pieces[..<offset])
            var padded = seed.pitches
            while padded.count < count { padded.append(.flat) }
            rotated.pitches = Array(padded[offset...] + padded[..<offset])
            rotated.gateSeams = seed.gateSeams.map { ($0 - offset + count) % count }.sorted()
            let walk = seed.walk()
            rotated.origin = walk.placed[offset].entry
            rotated.originHeight = walk.placed[offset].entryHeight
            codes.insert(TrackCode.encode(rotated))
        }
        XCTAssertEqual(
            codes.count, 1,
            "the same ring written from \(count) starting points gave \(codes.count) codes")
    }

    /// Normalizing preserves the track: the canonical form compiles to the same
    /// shape, gates and grid as the spelling it came from.
    func testNormalizingPreservesTheTrack() throws {
        let seed = try primitiveRing()
        let reference = try PieceCompiler.compile(seed, id: "ref")
        let count = seed.pieces.count
        for offset in [1, 5, 12] {
            var rotated = seed
            rotated.pieces = Array(seed.pieces[offset...] + seed.pieces[..<offset])
            var padded = seed.pitches
            while padded.count < count { padded.append(.flat) }
            rotated.pitches = Array(padded[offset...] + padded[..<offset])
            rotated.gateSeams = seed.gateSeams.map { ($0 - offset + count) % count }.sorted()
            let walk = seed.walk()
            rotated.origin = walk.placed[offset].entry
            rotated.originHeight = walk.placed[offset].entryHeight

            let track = try PieceCompiler.compile(rotated.normalized(), id: "ref")
            XCTAssertEqual(
                track.centerline.count, reference.centerline.count,
                "offset \(offset): same road")
            XCTAssertEqual(
                track.centerlineLength, reference.centerlineLength, accuracy: 0.01,
                "offset \(offset): same length")
            XCTAssertEqual(
                track.gates.count, reference.gates.count,
                "offset \(offset): same gate count")
            XCTAssertEqual(
                track.startSlots.count, reference.startSlots.count,
                "offset \(offset): same grid")
        }
    }

    /// A code round-trips to an equal layout — normalization must be idempotent,
    /// or re-saving a decoded track would drift.
    func testNormalizationIsIdempotent() throws {
        let once = TrackCode.encode(try primitiveRing())
        let twice = TrackCode.encode(try TrackCode.decode(once))
        XCTAssertEqual(once, twice, "encoding a decoded code must not change it")
    }

    /// **A track driven the other way is a DIFFERENT track**, and normalizing
    /// must never collapse the two. Rotation is a re-spelling of the same ring;
    /// reversal changes which way you drive it — every corner swaps hand, so it
    /// is a different course with a different code. Normalization only rotates.
    func testTheSameRingDrivenBackwardsIsADifferentTrack() throws {
        let seed = try primitiveRing()
        var reversed = seed
        // Walking the piece list backwards: the corners come in the opposite
        // order and each turns the other way relative to travel, so this is the
        // other direction round the same loop.
        reversed.pieces = seed.pieces.reversed()
        reversed.gateSeams = seed.gateSeams
        let forward = TrackCode.encode(seed)
        let backward = TrackCode.encode(reversed)
        XCTAssertNotEqual(
            forward, backward,
            "reversal is not a re-spelling — the two directions must stay distinct")
    }

    /// **The shipped codes are already canonical**, so normalization does not
    /// silently rewrite the built-ins. Each has its start line at index 0, which
    /// is the anchor, so re-encoding a decoded built-in reproduces its code
    /// byte-for-byte. If a future built-in is authored with the start line
    /// elsewhere, this fails and the stored code should be replaced with the
    /// canonical one rather than the rule bent.
    func testTheBuiltInCodesAreAlreadyCanonical() throws {
        for builtin in TrackLibrary.builtins {
            let layout = try TrackCode.decode(builtin.code)
            XCTAssertEqual(
                TrackCode.encode(layout), builtin.code,
                "\(builtin.id): stored code is not the canonical spelling")
        }
    }

    /// An OPEN chain (mid-build) must not be rotated — its first piece is where
    /// the author started and its ends are not interchangeable.
    func testAnOpenChainKeepsItsOrder() throws {
        // Primitives, so the comparison is not confounded by re-packing.
        let chain: [PieceID] = [
            Catalog.startGrid, Catalog.curve45MediumRight, Catalog.shortStraight,
        ]
        let layout = TrackLayout(pieces: chain, gateSeams: [0])
        XCTAssertFalse(layout.walk().openEnds.isEmpty, "this chain is open")
        XCTAssertEqual(
            layout.normalized().pieces, chain,
            "an open chain has no canonical rotation and must keep its order")
    }
}
