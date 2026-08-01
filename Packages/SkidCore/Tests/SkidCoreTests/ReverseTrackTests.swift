import SkidCore
import XCTest

@testable import SkidKit

/// **Turning a track around.** The start line's facing decides which way the
/// track is driven, and reversing it must reverse everything that follows from
/// direction: the centerline, the gate order, and the grid.
///
/// Done by reversing the LAYOUT rather than by a flag the compiler honours (which
/// is what the plan originally sketched). The compiler already derives the grid,
/// the gates and the centerline from the walked pieces, so a reversed ring gives
/// all three for free — and the reversal is the same geometric mirror that already
/// makes building backwards read correctly.
@MainActor
final class ReverseTrackTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    private func ring() throws -> CouchGame {
        let game = CouchGame()
        game.editorLayout = try TrackCode.decode(
            "AS0BDh8KDBEFeQUFFXoGBHgEAgQABAgMAwUC0ADwAA")
        game.clearUndoHistory()
        return game
    }

    /// The road does not move: reversing is about DIRECTION, not shape. Every
    /// piece's centerline must still cover the same ground.
    func testReversingKeepsTheSameRoad() throws {
        let game = try ring()
        let before = sampledRoad(game.editorLayout!)

        XCTAssertTrue(game.editorReverseDirection())

        XCTAssertEqual(
            sampledRoad(game.editorLayout!), before,
            "reversing must turn the track around, not reshape it")
    }

    /// And it still closes, still validates, and keeps its piece count.
    func testAReversedRingIsStillAValidTrack() throws {
        let game = try ring()
        let count = game.editorLayout!.pieces.count
        XCTAssertTrue(game.editorReverseDirection())

        let layout = game.editorLayout!
        XCTAssertEqual(layout.pieces.count, count)
        XCTAssertTrue(layout.walk().openEnds.isEmpty, "the ring must stay closed")
        XCTAssertTrue(
            TrackValidator.validate(layout).isSaveable,
            "problems: \(TrackValidator.validate(layout).problems)")
    }

    /// **The driving direction actually flips.** Follow the centerline: each piece's
    /// travel should be the opposite of what it was.
    func testTheDrivingDirectionFlips() throws {
        let game = try ring()
        let before = game.editorLayout!.walk().placed[0]
        let beforeDir = Vec2(angle: before.entry.heading.radians)

        XCTAssertTrue(game.editorReverseDirection())

        // The piece now covering that same ground must be driven the other way.
        let after = game.editorLayout!.walk().placed
        let match = after.first {
            $0.entry.position == before.exits[0].position
        }
        let afterDir = try XCTUnwrap(match.map { Vec2(angle: $0.entry.heading.radians) })
        XCTAssertLessThan(
            beforeDir.dot(afterDir), 0,
            "the road at that spot should now be driven the opposite way")
    }

    /// **The grid moves to the other side of the line**, since the cars line up
    /// behind the start relative to travel.
    func testTheGridMovesToTheOtherSideOfTheLine() throws {
        let game = try ring()
        let forwardLayout = game.editorLayout!
        let forward = try PieceCompiler.compile(forwardLayout)
        XCTAssertTrue(game.editorReverseDirection())
        let reversed = try PieceCompiler.compile(game.editorLayout!)

        // Grid slots sit BEHIND the start line relative to travel, in both facings.
        //
        // Measured against the compiled FINISH GATE, which the compiler emits last.
        // Not the walked start piece's exit: the compiler re-frames a track onto what
        // it occupies, so slots live in framed space and walk coordinates do not —
        // comparing across the two reads as a 443-unit error that isn't there.
        for track in [forward, reversed] {
            let line = track.gates.last!
            let mid = (line.a + line.b) * 0.5
            let dir = Vec2(angle: track.startHeading)
            for slot in track.startSlots {
                XCTAssertLessThanOrEqual(
                    (slot - mid).dot(dir), 1,
                    "a grid slot sat ahead of the start line")
            }
        }
        // And they are genuinely on opposite sides of the world.
        XCTAssertLessThan(
            Vec2(angle: forward.startHeading).dot(Vec2(angle: reversed.startHeading)), 0,
            "the grid should face the other way after reversing")
    }

    /// The AI can lap it — the strongest end-to-end check that direction is
    /// coherent through the centerline, the gates and the standings.
    func testTheAILapsAReversedTrack() throws {
        let game = try ring()
        XCTAssertTrue(game.editorReverseDirection())
        let track = try PieceCompiler.compile(game.editorLayout!)

        var race = Race(
            track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
        var driver = AIDriver()
        var ticks = 0
        while race.cars[0].progress.finishedAt == nil, ticks < 120 * Race.tickRate {
            let input = driver.input(car: race.cars[0].state, track: race.track)
            race.advance(inputs: [PlayerID(0): input])
            ticks += 1
        }
        XCTAssertNotNil(
            race.cars[0].progress.finishedAt, "the AI could not lap the reversed track")
    }

    /// Reversing twice is the identity — the same track, byte for byte.
    func testReversingTwiceComesBack() throws {
        let game = try ring()
        let original = TrackCode.encode(game.editorLayout!)
        XCTAssertTrue(game.editorReverseDirection())
        XCTAssertNotEqual(
            TrackCode.encode(game.editorLayout!), original,
            "a reversed track is a DIFFERENT track — normalization keeps reversal")
        XCTAssertTrue(game.editorReverseDirection())
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), original)
    }

    /// It is undoable, like every other edit.
    func testReversingIsUndoable() throws {
        let game = try ring()
        let original = TrackCode.encode(game.editorLayout!)
        XCTAssertTrue(game.editorReverseDirection())
        game.editorUndo()
        XCTAssertEqual(TrackCode.encode(game.editorLayout!), original)
    }

    /// An OPEN chain has no driving direction to speak of yet — refuse rather than
    /// half-reverse something the author is still drawing.
    func testAnOpenChainIsNotReversed() {
        let game = CouchGame()
        game.editorReset()
        game.clearUndoHistory()
        for _ in 0..<3 { _ = game.editorAppend(Catalog.shortStraight) }
        XCTAssertFalse(game.editorReverseDirection())
    }

    /// The button's enabled state must agree with what the action actually does,
    /// so it greys out instead of taking a tap and refusing it.
    func testTheButtonIsOnlyOfferedWhenReversingWorks() throws {
        let open = CouchGame()
        open.editorReset()
        for _ in 0..<3 { _ = open.editorAppend(Catalog.shortStraight) }
        XCTAssertFalse(open.editorCanReverseDirection)

        let closed = try ring()
        XCTAssertTrue(closed.editorCanReverseDirection)
    }

    /// Every point of road, as a comparable set — the shape, independent of which
    /// way it is driven or how the ring is spelled.
    private func sampledRoad(_ layout: TrackLayout) -> Set<String> {
        Set(
            layout.walk().placed.flatMap { placed in
                placed.centerlineSamples(degreesPerSample: 15).map {
                    "\(Int($0.x.rounded()))|\(Int($0.y.rounded()))"
                }
            })
    }
}
