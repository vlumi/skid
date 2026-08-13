import XCTest

@testable import SkidCore

/// **One mutation API, one place that remaps.** Three things are keyed to piece
/// indices — `gateSeams` (seam *i* is piece *i*'s entry port), `fitters`, and the
/// parallel `pitches` array — so every insert, removal and rotation has to move
/// all three together. Editing `pieces` directly is how each operation grows its
/// own off-by-one; these tests pin the contract that stops that.
///
/// The property under test is **identity preservation**: keyed data must still
/// point at the same PIECE it pointed at before, not the same index.
final class LayoutMutationTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    /// A ring with pitches, gates and a distinguishable piece at every index, so
    /// a mis-remap shows up as the wrong piece rather than coincidentally passing.
    private func ring() -> TrackLayout {
        TrackLayout(
            pieces: [
                Catalog.startGrid, Catalog.shortStraight, Catalog.curve45MediumLeft,
                Catalog.longStraight, Catalog.curve45MediumRight, Catalog.shortStraight,
            ],
            pitches: [.flat, .up, .up, .flat, .down, .down],
            gateSeams: [0, 2, 4])
    }

    // MARK: - insert

    /// Inserting shifts every later piece's keyed data along with it — and leaves
    /// earlier data alone.
    func testInsertMovesKeyedDataWithTheirPieces() {
        var layout = ring()
        layout.fitters = [4: Fitter(radius: 100, angle: 0.3, length: 50, stepsLeft: true)]

        layout.insert(Catalog.shortStraight, pitch: .up, at: 2)

        XCTAssertEqual(
            layout.pieces,
            [
                Catalog.startGrid, Catalog.shortStraight, Catalog.shortStraight,
                Catalog.curve45MediumLeft, Catalog.longStraight, Catalog.curve45MediumRight,
                Catalog.shortStraight,
            ])
        // The inserted piece owns its pitch; the ones it pushed keep theirs.
        XCTAssertEqual(layout.pitch(at: 1), .up, "piece before the cut is untouched")
        XCTAssertEqual(layout.pitch(at: 2), .up, "the inserted piece's own pitch")
        XCTAssertEqual(layout.pitch(at: 3), .up, "the pushed curve keeps its climb")
        XCTAssertEqual(layout.pitch(at: 5), .down)
        XCTAssertEqual(layout.pitch(at: 6), .down)
        // Gates at/after the cut shift; the one before it does not.
        XCTAssertEqual(layout.gateSeams, [0, 3, 5])
        // The fitter followed its piece from 4 to 5.
        XCTAssertEqual(Array(layout.fitters.keys), [5])
    }

    /// Inserting at the end is what appending already does — the API must agree
    /// with it, or the editor's two paths diverge.
    func testInsertingAtTheEndMatchesAppend() {
        var inserted = ring()
        var appended = ring()
        inserted.insert(Catalog.longStraight, pitch: .down, at: inserted.pieces.count)
        appended.append(contentsOf: [(id: Catalog.longStraight, pitch: .down)])
        XCTAssertEqual(inserted, appended)
    }

    // MARK: - remove

    /// Removing pulls later keyed data back — and drops what belonged to the
    /// victim rather than silently re-pointing it at its neighbor.
    func testRemoveDropsTheVictimsDataAndPullsTheRestBack() {
        var layout = ring()
        layout.fitters = [
            2: Fitter(radius: 100, angle: 0.3, length: 50, stepsLeft: true),
            4: Fitter(radius: 200, angle: 0.4, length: 60, stepsLeft: false),
        ]

        layout.remove(at: 2)

        XCTAssertEqual(
            layout.pieces,
            [
                Catalog.startGrid, Catalog.shortStraight, Catalog.longStraight,
                Catalog.curve45MediumRight, Catalog.shortStraight,
            ])
        XCTAssertEqual(layout.pitch(at: 1), .up)
        XCTAssertEqual(layout.pitch(at: 2), .flat, "the long straight, pulled back")
        XCTAssertEqual(layout.pitch(at: 3), .down)
        // The gate ON the removed piece goes with it; the later one pulls back.
        XCTAssertEqual(layout.gateSeams, [0, 3])
        // Index 2's fitter is gone; index 4's survives at 3 with its own shape.
        XCTAssertEqual(Array(layout.fitters.keys), [3])
        XCTAssertEqual(layout.fitters[3]?.radius, 200, "the SURVIVING fitter, not the dead one")
    }

    /// Removing the last piece is what the editor's delete already does.
    func testRemovingTheLastMatchesRemoveLastPiece() {
        var removed = ring()
        var popped = ring()
        removed.remove(at: removed.pieces.count - 1)
        popped.removeLastPiece()
        XCTAssertEqual(removed.pieces, popped.pieces)
        XCTAssertEqual(removed.pitches, popped.pitches)
    }

    // MARK: - rotate

    /// A real closed ring — the clover built-in, which has pitches, a raised
    /// baseline and self-crossing, so rotation is tested against the awkward case
    /// rather than a flat circle. `rotate` only acts on closed rings (an open
    /// chain's ends are not interchangeable), so the fixture has to be one.
    private func closedRing() throws -> TrackLayout {
        try TrackCode.decode(
            TestTracks.Code.clover)
    }

    /// Rotation is a re-spelling: the surviving geometry must not move, which is
    /// what makes ring deletion (rotate-then-pop) free.
    func testRotateKeepsGeometryAndKeyedDataOnTheirPieces() throws {
        let layout = try closedRing()
        let before = layout.walk()
        XCTAssertTrue(before.openEnds.isEmpty, "fixture must be a closed ring")
        let count = layout.pieces.count
        let offset = 5

        var rotated = layout
        rotated.rotate(to: offset)

        XCTAssertEqual(
            rotated.pieces, Array(layout.pieces[offset...] + layout.pieces[..<offset]))
        // Every piece keeps its OWN pitch through the rotation.
        for index in 0..<count {
            XCTAssertEqual(
                rotated.pitch(at: index), layout.pitch(at: (index + offset) % count),
                "pitch at \(index) came from the wrong piece")
        }
        XCTAssertEqual(
            rotated.gateSeams, layout.gateSeams.map { ($0 - offset + count) % count }.sorted())
        // The geometry is unchanged: each piece sits exactly where it did, just
        // enumerated from a different starting point.
        let after = rotated.walk()
        XCTAssertNil(after.failure)
        XCTAssertTrue(after.openEnds.isEmpty, "the ring must still be closed")
        for (index, piece) in after.placed.enumerated() {
            let original = before.placed[(index + offset) % count]
            XCTAssertEqual(piece.id, original.id)
            XCTAssertEqual(piece.entry, original.entry, "piece \(index) moved")
            XCTAssertEqual(piece.entryHeight, original.entryHeight, accuracy: 1e-12)
        }
    }

    /// An OPEN chain is left alone — rotating one would splice its tail onto its
    /// head, and its two ends are not interchangeable.
    func testRotateDeclinesOnAnOpenChain() {
        let open = ring()
        var rotated = open
        rotated.rotate(to: 2)
        XCTAssertEqual(rotated, open)
    }

    /// `normalized()` must keep producing exactly what it produces today — it
    /// becomes a caller of `rotate`, and a share code is an identity.
    func testNormalizedIsUnchangedByTheRewrite() throws {
        // Spelled from a non-canonical start so normalization has work to do.
        let seed = try TrackCode.decode(
            TrackCode.encode(
                TrackLayout(
                    pieces: [
                        Catalog.startGrid, Catalog.curve90MediumRight,
                        Catalog.curve90MediumRight, Catalog.curve90MediumRight,
                        Catalog.curve90TightLeft, Catalog.shortStraight, Catalog.shortStraight,
                        Catalog.curve90TightRight, Catalog.curve90MediumRight,
                        Catalog.jog240Right,
                    ], gateSeams: [0, 3, 6])))
        let count = seed.pieces.count
        for offset in 1..<count {
            var spelled = seed
            spelled.rotate(to: offset)
            XCTAssertEqual(
                TrackCode.encode(spelled.normalized()), TrackCode.encode(seed),
                "spelling from \(offset) must normalize back to the canonical code")
        }
    }

    // MARK: - the property

    /// Any sequence of mutations keeps the invariants: `pitches` never longer
    /// than `pieces`, every gate seam and fitter key in range, and each surviving
    /// keyed datum still on the piece it started on (tracked by identity).
    ///
    /// The identity audit is the real assertion. Indices are what the API moves,
    /// so checking indices proves nothing; instead every piece carries a tag
    /// through the whole sequence, and the fitter must always be found on the
    /// piece whose tag it started on.
    func testAnySequenceOfMutationsKeepsTheInvariants() {
        var rng = SeededRNG(seed: 0xED17)
        for _ in 0..<200 {
            var layout = ring()
            let fitterTag = 3
            layout.fitters = [
                fitterTag: Fitter(radius: 100, angle: 0.3, length: 50, stepsLeft: true)
            ]
            // Tag each piece with a unique identity so a remap can be audited:
            // the tag rides along in a parallel array we mutate the same way.
            // -1 marks a piece inserted during the run (no original identity).
            var tags = Array(0..<layout.pieces.count)

            for _ in 0..<8 {
                switch rng.next() % 3 {
                case 0:
                    let at = Int(rng.next() % UInt64(layout.pieces.count + 1))
                    layout.insert(Catalog.shortStraight, pitch: .up, at: at)
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
                    // Rotation declines on an open chain (this fixture is one),
                    // so only re-order the tags if it actually happened.
                    if layout.pieces != before { tags = Array(tags[to...] + tags[..<to]) }
                }

                XCTAssertLessThanOrEqual(
                    layout.pitches.count, layout.pieces.count, "pitches outran pieces")
                for seam in layout.gateSeams {
                    XCTAssertTrue(
                        layout.pieces.indices.contains(seam), "gate seam \(seam) out of range")
                }
                for key in layout.fitters.keys {
                    XCTAssertTrue(
                        layout.pieces.indices.contains(key), "fitter key \(key) out of range")
                }
                XCTAssertEqual(tags.count, layout.pieces.count)
                // Identity: the fitter is either gone (its piece was removed) or
                // sitting on exactly the piece it began on.
                if let key = layout.fitters.keys.first {
                    XCTAssertEqual(
                        tags[key], fitterTag,
                        "the fitter drifted onto another piece (tag \(tags[key]))")
                } else {
                    XCTAssertFalse(
                        tags.contains(fitterTag),
                        "the fitter vanished while its piece is still here")
                }
            }
        }
    }
}
