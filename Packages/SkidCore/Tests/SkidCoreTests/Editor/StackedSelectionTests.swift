import XCTest

@testable import SkidCore

/// **Selecting a piece when the map is a 2D projection of a stack.**
///
/// A tap on a track that climbs through three storeys is ambiguous by construction:
/// several pieces lie under the finger. Three things follow, all reported from
/// device.
final class StackedSelectionTests: XCTestCase {
    private func walk() throws -> WalkResult {
        try TrackCode.decode(TestTracks.Code.towerOfBabel).walk()
    }

    /// **The reach follows the drawn road.** A flat `width / 2` made a raised piece
    /// harder to hit than it looks: the asphalt under your finger reaches further than
    /// the tap was accepted, by 20% per storey.
    func testARaisedPieceIsHittableAcrossItsFullWidth() throws {
        let walk = try walk()
        // A piece as high as the track goes.
        let index = try XCTUnwrap(
            walk.placed.indices.max {
                max(walk.placed[$0].entryHeight, walk.placed[$0].exitHeight)
                    < max(walk.placed[$1].entryHeight, walk.placed[$1].exitHeight)
            })
        let placed = walk.placed[index]
        let top = max(placed.entryHeight, placed.exitHeight)
        XCTAssertGreaterThan(top, 1.5, "the fixture must have a high piece")

        let samples = placed.centerlineSamples(degreesPerSample: 12)
        let mid = samples[samples.count / 2]
        let next = samples[min(samples.count - 1, samples.count / 2 + 1)]
        let across = (next - mid).normalized.perpendicular
        // Just inside the DRAWN edge — beyond a flat half-width, but real asphalt.
        let flatHalf = Double(PieceCatalog.width) / 2
        let drawnHalf = flatHalf * Elevation.scale(atHeight: top)
        XCTAssertGreaterThan(drawnHalf, flatHalf + 4, "the drawn road must be wider")
        let at = mid + across * (flatHalf + (drawnHalf - flatHalf) / 2)
        XCTAssertNotNil(
            walk.piece(nearWorld: at),
            "a tap on the raised piece's own asphalt must select something")
    }

    /// **Ties break by height, topmost first.** On a stack the centerlines can be a
    /// pixel apart, and "nearest" then picks arbitrarily between storeys.
    func testAStackedTapPicksTheTopmostPiece() throws {
        let walk = try walk()
        var checked = 0
        for (index, placed) in walk.placed.enumerated() {
            let samples = placed.centerlineSamples(degreesPerSample: 12)
            guard samples.count > 1 else { continue }
            let mid = samples[samples.count / 2]
            // Which pieces pass within a road width of this point?
            let overlapping = walk.placed.enumerated().filter { other in
                other.element.centerlineSamples(degreesPerSample: 12)
                    .contains { ($0 - mid).length < 6 }
            }
            guard overlapping.count > 1 else { continue }
            let highest = try XCTUnwrap(
                overlapping.max {
                    max($0.element.entryHeight, $0.element.exitHeight)
                        < max($1.element.entryHeight, $1.element.exitHeight)
                })
            let picked = walk.piece(nearWorld: mid)
            let pickedTop = picked.map {
                max(walk.placed[$0].entryHeight, walk.placed[$0].exitHeight)
            }
            XCTAssertEqual(
                try XCTUnwrap(pickedTop),
                max(highest.element.entryHeight, highest.element.exitHeight),
                accuracy: 0.01,
                "a tap where pieces stack must pick the topmost, not an arbitrary one")
            checked += 1
            _ = index
            if checked > 8 { break }
        }
        XCTAssertGreaterThan(checked, 0, "the fixture must have stacked pieces")
    }

    /// **A level filter is the only way to reach a covered piece.** Reported: with
    /// three pieces stacked there is no clean way to rail the lowest one — you would
    /// have to delete the pieces above it.
    func testAFilterReachesACoveredPiece() throws {
        let walk = try walk()
        // A point where a low piece is covered by a higher one.
        for (index, placed) in walk.placed.enumerated() {
            let low = max(placed.entryHeight, placed.exitHeight)
            guard Track.level(of: low) == 0 else { continue }
            let samples = placed.centerlineSamples(degreesPerSample: 12)
            let mid = samples[samples.count / 2]
            let covered = walk.placed.contains { other in
                max(other.entryHeight, other.exitHeight) > low + 0.6
                    && other.centerlineSamples(degreesPerSample: 12)
                        .contains { ($0 - mid).length < 6 }
            }
            guard covered else { continue }
            // Unfiltered, the tap takes the piece above.
            let unfiltered = walk.piece(nearWorld: mid)
            XCTAssertNotEqual(
                unfiltered, index, "unfiltered, a covered piece is not what a tap means")
            // Filtered to the ground, it takes this one.
            XCTAssertEqual(
                walk.piece(nearWorld: mid, onlyLevel: 0), index,
                "filtered to level 0, the tap must reach the covered piece")
            return
        }
        XCTFail("the fixture must have a covered ground piece")
    }

    /// The filter selects nothing on a storey the track does not use, rather than
    /// falling back to some other piece.
    func testAFilterOnAnEmptyStoreySelectsNothing() throws {
        let walk = try walk()
        let mid = walk.placed[0].centerlineSamples(degreesPerSample: 12)[1]
        XCTAssertNil(
            walk.piece(nearWorld: mid, onlyLevel: 99),
            "no piece is on storey 99, so the tap means nothing")
    }
}
