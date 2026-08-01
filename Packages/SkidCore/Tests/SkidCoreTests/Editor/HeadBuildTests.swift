import SkidCore
import XCTest

@testable import SkidKit

/// **Building backwards should read the way you are building.**
///
/// Prepending puts a piece BEFORE the current head, so what the author draws
/// going backwards is stored as the piece a car would drive going forwards — and
/// those are mirrored. Reported from device: standing at the head and wanting an
/// up-ramp turning left, the author had to tap DOWN-RIGHT, because that is what
/// the stored piece looks like in the driving direction.
///
/// So the palette speaks the author's direction and the model stores the driving
/// one: tapping up-left at the head stores down-right.
@MainActor
final class HeadBuildTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    private func chain() -> CouchGame {
        let game = CouchGame()
        game.editorReset()
        game.clearUndoHistory()
        for _ in 0..<3 { _ = game.editorAppend(Catalog.shortStraight) }
        game.editorSelect(game.editorLayout!.pieces.count - 1)
        return game
    }

    /// A LEFT curve tapped at the head is stored as the right-hand mirror.
    func testTappingLeftAtTheHeadStoresTheMirror() {
        let game = chain()
        game.editorSelect(0)  // the head
        XCTAssertTrue(game.editorPlace(Catalog.curve45MediumLeft))
        XCTAssertEqual(
            game.editorLayout!.pieces.first, Catalog.curve45MediumRight,
            "tapping left while building backwards should store the right-hand piece")
    }

    /// And a RIGHT curve stores the left-hand one. Checked as GEOMETRY, because a
    /// 90° is a compound: it expands to two 45° primitives, so the stored first id
    /// is a primitive rather than the 90° the palette offered.
    func testTappingRightAtTheHeadStoresTheMirror() {
        let game = chain()
        game.editorSelect(0)
        XCTAssertTrue(game.editorPlace(Catalog.curve90TightRight))
        // The stored run must be the SCREEN-LEFT arcs — the mirror of the
        // right-hand curve tapped. (`Piece.Segment.arc(left:)` is the math-CCW flag,
        // and the catalog passes `false` for a screen-left piece: the model's CCW
        // renders clockwise on a y-down canvas. So screen-left is `left: false`.)
        for index in 0..<2 {
            let arcs = PieceCatalog.piece(game.editorLayout!.pieces[index])!.paths[0]
                .compactMap { segment -> Bool? in
                    if case .arc(_, _, let left) = segment { return left }
                    return nil
                }
            XCTAssertEqual(arcs, [false], "piece \(index) should be the mirrored arc")
        }
    }

    /// The mirror map itself: every handed piece pairs with the same shape turning
    /// the other way, and pairing is mutual.
    func testTheMirrorMapIsConsistent() {
        for (id, piece) in PieceCatalog.all {
            let mirror = PieceCatalog.mirrored[id]
            XCTAssertNotNil(mirror, "piece \(id) has no mirror entry")
            XCTAssertEqual(
                PieceCatalog.mirrored[mirror!], id,
                "mirroring piece \(id) twice should come back to it")
            // Same shape, opposite handedness.
            let handed =
                piece.paths.first?.contains { segment in
                    if case .arc = segment { return true }
                    return false
                } ?? false
            if !handed {
                XCTAssertEqual(mirror, id, "a piece with no arcs is its own mirror")
            }
        }
    }

    /// **Up becomes down.** Climbing away from the head means the stored piece
    /// descends into it — the reported case exactly.
    func testTappingUpAtTheHeadStoresADescent() {
        let game = chain()
        game.editorSelect(0)
        XCTAssertTrue(game.editorPlace(Catalog.shortStraight, pitch: .up))
        XCTAssertEqual(
            game.editorLayout!.pitch(at: 0), .down,
            "climbing backwards is a descent in the driving direction")
    }

    /// Straights and flat pitch are unaffected — there is nothing to mirror. (The
    /// long straight expands to shorts, so check the SHAPE is still a straight
    /// rather than the id the palette offered.)
    func testStraightsAndFlatAreUnchanged() {
        let game = chain()
        game.editorSelect(0)
        XCTAssertTrue(game.editorPlace(Catalog.longStraight))
        let first = game.editorLayout!.walk().placed[0]
        XCTAssertEqual(
            first.entry.heading.step, first.exits[0].heading.step,
            "a straight must not gain a turn from being mirrored")
        XCTAssertEqual(game.editorLayout!.pitch(at: 0), .flat)
    }

    /// The TAIL is untouched: building forwards already matches the driving
    /// direction, so nothing is mirrored there.
    func testTheTailIsNotMirrored() {
        let game = chain()
        XCTAssertTrue(game.editorPlace(Catalog.curve45MediumLeft, pitch: .up))
        XCTAssertEqual(game.editorLayout!.pieces.last, Catalog.curve45MediumLeft)
        XCTAssertEqual(
            game.editorLayout!.pitch(at: game.editorLayout!.pieces.count - 1), .up)
    }

    /// **What the author drew is what appears.** The mirror is a storage detail, so
    /// the road laid at the head must match the road the same tap lays at the tail,
    /// just running the other way. Compare the turn each one makes.
    func testTheDrawnShapeMatchesWhatWasTapped() {
        // Tail: a left curve turns the road one way.
        let tail = chain()
        XCTAssertTrue(tail.editorPlace(Catalog.curve45MediumLeft))
        let tailWalk = tail.editorLayout!.walk()
        let tailTurn =
            tailWalk.placed.last!.exits[0].heading.step - tailWalk.placed.last!.entry.heading.step

        // Head: the same tap, and the piece it lays must turn the SAME way when
        // followed in the author's direction — which is the reverse of the list.
        let head = chain()
        head.editorSelect(0)
        XCTAssertTrue(head.editorPlace(Catalog.curve45MediumLeft))
        let headWalk = head.editorLayout!.walk()
        let headTurn =
            headWalk.placed[0].entry.heading.step - headWalk.placed[0].exits[0].heading.step

        XCTAssertEqual(
            ((tailTurn % 8) + 8) % 8, ((headTurn % 8) + 8) % 8,
            "the same tap should draw the same turn whichever end it is built from")
    }
}
