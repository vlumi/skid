import XCTest

@testable import SkidCore

/// **The start line is an ordinary piece.** It may sit anywhere on the ring, not
/// only at position 0, and the track behaves identically — the grid is built on
/// whichever piece IS the start line, and the finish gate is that piece's seam.
///
/// Three roles used to pile onto position 0: where the walk begins, where the
/// ring closes, and where the start line is. Only the last is really about the
/// start line, and conflating them meant a track could not be rotated (nor,
/// later, anchored anywhere else — see docs/flexible-tracks-plan.md).
final class StartPieceTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    /// A closed ring with the start line at position 0.
    private let ringStartFirst: [PieceID] = [
        Pieces.startGrid, Pieces.curve90MediumRight, Pieces.curve90MediumRight,
        Pieces.curve90MediumRight, Pieces.curve90TightLeft, Pieces.shortStraight,
        Pieces.shortStraight, Pieces.curve90TightRight, Pieces.curve90MediumRight,
        Pieces.jog240Right,
    ]

    /// The SAME ring, rotated so the start line lands mid-list. Rotating a
    /// closed ring cannot change its geometry, only where the walk begins.
    private func rotated(by offset: Int) -> [PieceID] {
        Array(ringStartFirst[offset...] + ringStartFirst[..<offset])
    }

    /// The start grid is built on the start LINE, wherever it sits — not on
    /// whatever happens to be first in the list.
    func testTheGridSitsOnTheStartLineNotOnPieceZero() throws {
        let first = try PieceCompiler.compile(
            TrackLayout(pieces: ringStartFirst, gateSeams: [0, 3, 6]), id: "a")
        // Rotate by 3: the start line moves to index 7, and the seams that were
        // 0/3/6 move with it.
        let offset = 3
        let moved = try PieceCompiler.compile(
            TrackLayout(
                pieces: rotated(by: offset),
                gateSeams: [0, 3, 6].map { ($0 - offset + 10) % 10 }),
            id: "b")

        // Same number of slots. (Not the same HEADING: the walk starts at the
        // list's first piece, so rotating the ring re-frames the whole track and
        // the start line's absolute bearing legitimately differs. What must hold
        // is that the grid sits AT the start line, which is checked below.)
        XCTAssertEqual(first.startSlots.count, moved.startSlots.count)
        // The grid's slots must lie on the road, at the start line — measured as
        // distance to the finish gate (the last gate, by runtime convention).
        for (label, track) in [("start-first", first), ("rotated", moved)] {
            let finish = try XCTUnwrap(track.gates.last)
            let mid = (finish.a + finish.b) * 0.5
            for slot in track.startSlots {
                XCTAssertLessThan(
                    slot.distance(to: mid), 3 * track.width,
                    "\(label): grid slots must sit at the finish line")
            }
        }
    }

    /// The finish gate is the start piece's seam. With the start line rotated
    /// away from position 0, seam 0 is an ordinary checkpoint and the finish
    /// must follow the start line.
    func testTheFinishGateFollowsTheStartLine() throws {
        let offset = 3
        let layout = TrackLayout(
            pieces: rotated(by: offset),
            gateSeams: [0, 3, 6].map { ($0 - offset + 10) % 10 })
        let track = try PieceCompiler.compile(layout, id: "b")
        let walk = layout.walk()
        let startIndex = try XCTUnwrap(
            walk.placed.firstIndex { $0.id == PieceCatalog.startPieceID })
        let finish = try XCTUnwrap(track.gates.last)
        let mid = (finish.a + finish.b) * 0.5
        let startExit =
            walk.placed[startIndex].exits[0].position.vec2
            + Vec2(track.layoutOffset.x, track.layoutOffset.y)
        XCTAssertLessThan(
            mid.distance(to: startExit), 1,
            "the last gate must be the START LINE's seam, not seam 0")
    }

    /// **A checkpoint at seam 0 is a real checkpoint** once the start line has
    /// moved. The editor used to skip seam 0 when drawing chevrons, on the
    /// assumption that it was the start line — so on a rotated ring it drew a
    /// chevron across the start line and left the actual seam 0 bare. The
    /// compiled gates are the authority, so assert against those: every marked
    /// seam becomes a gate, and the start line's is last.
    func testEveryMarkedSeamBecomesAGateWithTheStartLineLast() throws {
        let offset = 3
        let seams = [0, 3, 6].map { ($0 - offset + 10) % 10 }
        let layout = TrackLayout(pieces: rotated(by: offset), gateSeams: seams)
        let track = try PieceCompiler.compile(layout, id: "b")
        XCTAssertEqual(
            track.gates.count, seams.count,
            "every marked seam must compile to a gate, seam 0 included")
        let walk = layout.walk()
        let startIndex = try XCTUnwrap(
            walk.placed.firstIndex { $0.id == PieceCatalog.startPieceID })
        XCTAssertTrue(
            seams.contains(startIndex),
            "the rotated seam set must still include the start line's own seam")
    }

    /// A rotated ring still validates: rotation is not a geometry change.
    func testARotatedRingIsStillSaveable() {
        for offset in [0, 1, 3, 7] {
            let layout = TrackLayout(
                pieces: rotated(by: offset),
                gateSeams: [0, 3, 6].map { ($0 - offset + 10) % 10 })
            XCTAssertTrue(
                TrackValidator.validate(layout).isSaveable,
                "rotating by \(offset) must not break validity")
        }
    }
}
