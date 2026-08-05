import Foundation
import Testing

@testable import SkidCore
@testable import SkidKit

/// **The warp: vertical relocation with no length.** It is what moves a track
/// between levels across a gap — the gap itself is only absence of road, and the
/// flight is gravity acting on a car that drove off a wedge.
struct WarpTests {
    /// Start, a full-level climb, then `ids`.
    ///
    /// The climb is **two pitched short straights, not the `rampUp` compound**: a
    /// layout always holds primitives (compounds exist only inside the byte stream,
    /// see `PiecePacking`), and hand-building one with a compound in it breaks the
    /// index stability that keyed data — warp drops, decals, rails — relies on.
    private func rampThen(_ ids: [PieceID]) -> TrackLayout {
        typealias Catalog = PieceCatalog.ID
        return TrackLayout(
            pieces: [Catalog.startGrid, Catalog.shortStraight, Catalog.shortStraight] + ids,
            pitches: [.flat, .up, .up])
    }

    /// A warp occupies **no ground**: it changes height and nothing else.
    @Test func aWarpHasNoLength() throws {
        let placed = try #require(
            TrackLayout(pieces: [PieceCatalog.ID.warp]).walk().placed.first)
        #expect(placed.entry.position == placed.exits[0].position)
        #expect(placed.entry.heading == placed.exits[0].heading)
    }

    /// It drops the road, and the pieces after it continue at the lower height.
    @Test func aWarpDropsEverythingAfterIt() {
        var layout = rampThen([PieceCatalog.ID.warp, PieceCatalog.ID.straight])
        layout.warpDrops = [3: -1]
        let placed = layout.walk().placed
        #expect(placed[2].exitHeight == 1, "the ramp should climb a level")
        #expect(placed[3].exitHeight == 0, "the warp should drop back to the ground")
        #expect(placed[4].entryHeight == 0, "road after the warp continues low")
    }

    /// **Never below the world's floor.** A too-deep warp lands on the floor rather
    /// than making road under the world — clamped in the walk, so such a layout is
    /// still drivable instead of invalid.
    @Test func aWarpCannotGoBelowTheFloor() {
        var layout = rampThen([PieceCatalog.ID.warp, PieceCatalog.ID.straight])
        layout.warpDrops = [3: -9]
        let floor = Track.levelHeight * Double(Track.lowestLevel)
        #expect(layout.walk().placed[3].exitHeight == floor)
    }

    /// **Never upward.** Nothing lifts a car, so a positive drop is not a road.
    @Test func aWarpNeverRises() {
        var layout = rampThen([PieceCatalog.ID.warp])
        layout.warpDrops = [3: 1]
        #expect(layout.walk().placed[3].climb <= 0)
    }

    // MARK: - The down/up arrows

    /// Down seeds one warp then DEEPENS it — never a chain. Two adjacent warps
    /// describe the same road as one deeper warp, so only one form is stored.
    @Test func steppingDownDeepensASingleWarp() {
        var layout = rampThen([])
        #expect(!layout.endsInWarp)

        layout = layout.warpedDeeper()
        let afterFirst = layout.pieces.count
        #expect(layout.endsInWarp)
        #expect(layout.warpDrops[layout.pieces.count - 1] == -TrackLayout.warpStep)

        layout = layout.warpedDeeper()
        #expect(layout.pieces.count == afterFirst, "a second tap added a piece")
        #expect(layout.warpDrops[layout.pieces.count - 1] == -TrackLayout.warpStep * 2)
    }

    /// Up shallows, and removes the warp at zero — returning the original layout,
    /// so the arrows are each other's inverse.
    @Test func steppingUpRemovesTheWarpAtZero() throws {
        let original = rampThen([])
        var layout = original.warpedDeeper().warpedDeeper()
        layout = try #require(layout.warpedShallower())
        #expect(layout.endsInWarp, "one step up from -1 should still be a warp")

        layout = try #require(layout.warpedShallower())
        #expect(!layout.endsInWarp, "a zero-drop warp must be removed, not kept")
        #expect(layout.pieces == original.pieces)
        #expect(layout.warpDrops.isEmpty)
    }

    /// With no warp there is nothing to shallow, so the arrow reports that rather
    /// than silently doing nothing.
    @Test func steppingUpWithoutAWarpIsRefused() {
        #expect(rampThen([]).warpedShallower() == nil)
    }

    // MARK: - Encoding

    /// A warp survives the share code, and a **one-level** drop — the common
    /// deck-to-ground jump — costs no bytes at all.
    @Test func warpDropsRoundTripAndTheDefaultIsFree() throws {
        var layout = rampThen([PieceCatalog.ID.gap, PieceCatalog.ID.warp])
        layout.warpDrops = [4: -Track.levelHeight]
        let byDefault = TrackCode.encode(layout)

        var custom = layout
        custom.warpDrops = [4: -Track.levelHeight * 1.5]
        let explicit = TrackCode.encode(custom)
        #expect(explicit.count > byDefault.count, "a non-default drop must be encoded")

        // Indexed by FINDING the warp, not by position: a ramp packs into pitched
        // primitives, so decoding shifts every index after it.
        let back = try TrackCode.decode(explicit)
        let warpIndex = try #require(back.pieces.firstIndex(of: PieceCatalog.ID.warp))
        #expect(back.warpDrop(at: warpIndex) == -Track.levelHeight * 1.5)

        // The default drop still lands the road back on the ground.
        let plain = try TrackCode.decode(byDefault)
        #expect(plain.walk().placed.last?.exitHeight == 0)
    }

    /// A warp's drop follows its piece when the layout is edited — the sixth
    /// index-keyed thing every mutation has to remap.
    @Test func aWarpDropFollowsItsPieceThroughAnInsert() {
        var layout = rampThen([PieceCatalog.ID.warp])
        layout.warpDrops = [3: -Track.levelHeight]
        layout.insert(PieceCatalog.ID.straight, pitch: .flat, at: 1)
        #expect(layout.warpDrops == [4: -Track.levelHeight], "got \(layout.warpDrops)")
    }
}

/// **Building on from a warped end.** The warp becomes the last piece, so anything
/// that tracks "the tail" has to follow it — the editor's palette greys out
/// entirely otherwise, which is how this shipped and was caught on device: you
/// could drop the road and then not continue it.
@MainActor
struct WarpBuildEndTests {
    private func gameWithARamp() -> CouchGame {
        let game = CouchGame()
        game.editorLayout = TrackLayout(
            pieces: [PieceCatalog.ID.startGrid, PieceCatalog.ID.shortStraight],
            pitches: [.flat, .up])
        game.editorSelection = 1
        return game
    }

    @Test func theBuildEndFollowsTheWarp() {
        let game = gameWithARamp()
        #expect(game.editorActiveEnd == .tail)

        #expect(game.editorStepWarp(deeper: true))
        let last = (game.editorLayout?.pieces.count ?? 0) - 1
        #expect(
            game.editorSelectedPiece == last,
            "the selection must move onto the warp, or the palette greys out")
        #expect(game.editorActiveEnd == .tail, "the tail must still be live after a warp")
    }

    /// And the road actually continues **at the lowered height**.
    @Test func roadAfterAWarpContinuesLower() throws {
        let game = gameWithARamp()
        #expect(game.editorStepWarp(deeper: true))
        #expect(game.editorCanPlace(PieceCatalog.ID.shortStraight), "palette must stay enabled")
        #expect(game.editorPlace(PieceCatalog.ID.shortStraight))

        let placed = try #require(game.editorLayout).walk().placed
        #expect(placed[1].exitHeight == TrackLayout.warpStep, "the ramp climbed half a level")
        #expect(placed.last?.exitHeight == 0, "road after the warp sits back at the bottom")
    }

    /// A gap too — that is the whole point of dropping: jump, then land lower.
    @Test func aGapCanFollowAWarp() {
        let game = gameWithARamp()
        #expect(game.editorStepWarp(deeper: true))
        #expect(game.editorCanPlace(PieceCatalog.ID.gap))
        #expect(game.editorPlace(PieceCatalog.ID.gap))
        #expect(game.editorLayout?.pieces.last == PieceCatalog.ID.gap)
    }

    /// Stepping a warp is **one undo**, like any other placement.
    @Test func aWarpStepIsUndoable() throws {
        let game = gameWithARamp()
        let before = try #require(game.editorLayout).pieces
        #expect(game.editorStepWarp(deeper: true))
        #expect(game.editorLayout?.pieces != before)
        game.editorUndo()
        #expect(game.editorLayout?.pieces == before, "a warp step must be undoable in one go")
    }
}
