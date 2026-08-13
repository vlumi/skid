import Foundation

@testable import SkidCore

/// Fixtures owned by the tests, for properties the shipping built-ins no
/// longer guarantee. The eight used to double as "a track with a steep ramp";
/// when it was rebuilt from gentle pitched sweeps, every test that scavenged
/// it for steepness lost its fixture — so the steep bridge lives here instead,
/// immune to built-in redesigns.
enum TestTracks {
    /// Share codes reused across suites. Named here rather than pasted as
    /// 40-character literals at each site: the strings are unreadable, and a
    /// format change (or a re-canonicalized built-in) otherwise means hunting
    /// every copy.
    enum Code {
        /// 17 pieces, closed, four gates, climbs to a deck and back. The
        /// general-purpose ring — selection, undo, gate mode, reversal.
        /// A user-built three-storey track: climbs to height 3, and its two loops
        /// run close enough that the gate corridor's neighbor-lane cap bites —
        /// which is what makes a mis-scaled gate span visible.
        static let threeStorey =
            "AVUBEB95BAQEBAQEAXoDAwMDAwMCAgAHAwUC0ALQAAgOAQIDBAUGBwgJCgsMDQ7-INRVqm6d8X"
            + "-Zz31Xyv_B5EfSuSdQd8AMmV7LfVyHANic_0BO1NraidT3y-SNM5q8Sps4ByNedwFz4KqFdj"
            + "WbfR5h4uhdYWdYBfKovwjh8QQlikSc1_ajaH-AiWJQiirb4iUM"
        /// A user-built spiral: climbs 0→3 in half-level stages and descends the
        /// same way, so a ramp at every storey passes over road below it. That is
        /// what exposed embankments filling from the ground rather than from the
        /// storey their ramp stands on.
        static let spiralToThree =
            "AfoBFR95BAQQAQMDDwEDAw8BegQEBAQEBAIFAAQKFBoDBQLQAtAA"
        /// The reported "tower of babel": road at all four storeys, fully railed,
        /// with decks stacked over one another. The hard case for the see-through
        /// window — a car may be one, two OR three storeys below a road.
        static let towerOfBabel =
            "AfIBFR95BAQQAQMDDwEDAw8BegQEBAQEBAIFAAQKFBoDBQLQAtAACB8AAQIDBAUG"
            + "BwgJCgsMDQ4PEBESExQVFhcYGRobHB0e"
        static let bridgeRing = "Ad0BDh8KDBEFeQUFFXoGBHgEAgQABAgMAwUC0ADwAAgGCgsMDQ4P"
        /// The clover: 47 pieces, closed, three gates, two crossings.
        static let clover = "AasBGR8eAQ95AwMBHgEPAwMBHgEPAwMBHgEPAwMCAwAXIwMFAeAB4AAFAQI"
        /// The clover mid-build: 46 pieces, still open at both ends.
        static let cloverOpen = "AQUBGh8PeQMDAR4BDwMDAR4BDwMDAR4BDwMDAXoAAgEAAwUDwAHgAA"
    }

    /// A closed rectangle carrying a full-height straight climb: start → up →
    /// deck → down, the steepest climb the catalog makes.
    static func steepBridge() -> Track {
        typealias Catalog = PieceCatalog.ID
        let pieces: [PieceID] = [
            Catalog.startGrid, Catalog.rampUp, Catalog.straight, Catalog.rampDown,
            Catalog.curve90TightLeft, Catalog.straight, Catalog.curve90TightLeft,
            Catalog.longStraight, Catalog.straight, Catalog.straight,
            Catalog.curve90TightLeft, Catalog.straight, Catalog.curve90TightLeft,
        ]
        let layout = TrackLayout(pieces: pieces, gateSeams: [0, 4])
        // A fixture that stops compiling is a broken test, not a runtime state.
        // swiftlint:disable:next force_try
        return try! PieceCompiler.compile(layout, id: "steep-bridge")
    }

    /// A closed rectangle with a **jump on the back straight**: a wedge ramp up,
    /// a gap, then a warp back down to the ground.
    ///
    /// This is what a jump is now — three ordinary pieces, no special "jump" piece
    /// and no launch line. The car flies because it drove off a real slope.
    static func jumpRing() -> Track {
        typealias Catalog = PieceCatalog.ID
        let pieces: [PieceID] = [
            Catalog.startGrid, Catalog.longStraight, Catalog.longStraight,
            Catalog.curve90TightLeft, Catalog.straight, Catalog.curve90TightLeft,
            Catalog.longStraight, Catalog.straight, Catalog.shortStraight,
            Catalog.rampUp, Catalog.gap, Catalog.warp,
            Catalog.curve90TightLeft, Catalog.straight, Catalog.curve90TightLeft,
        ]
        let layout = TrackLayout(pieces: pieces, gateSeams: [0, 6])
        // swiftlint:disable:next force_try
        return try! PieceCompiler.compile(layout, id: "jump-ring")
    }

    /// `jumpRing()` with **every piece railed** — for checking that a gap refuses a
    /// railing the author asked for.
    static func railedJumpRing() -> Track {
        typealias Catalog = PieceCatalog.ID
        let pieces: [PieceID] = [
            Catalog.startGrid, Catalog.longStraight, Catalog.longStraight,
            Catalog.curve90TightLeft, Catalog.straight, Catalog.curve90TightLeft,
            Catalog.longStraight, Catalog.straight, Catalog.shortStraight,
            Catalog.rampUp, Catalog.gap, Catalog.warp,
            Catalog.curve90TightLeft, Catalog.straight, Catalog.curve90TightLeft,
        ]
        var layout = TrackLayout(pieces: pieces, gateSeams: [0, 6])
        layout.railed = Set(pieces.indices)
        // swiftlint:disable:next force_try
        return try! PieceCompiler.compile(layout, id: "railed-jump-ring")
    }

    /// The jump **raised to a deck**: climb to 1, climb again onto the lip at 2,
    /// gap, then warp two levels down to the ground.
    ///
    /// Undershooting falls two storeys, so height is a clear witness of a missed
    /// jump — which is what the flight tests measure.
    static func elevatedJumpRing() -> Track {
        typealias Catalog = PieceCatalog.ID
        // **`jumpRing()`'s geometry, with one 2U straight swapped for a 2U ramp** so
        // the whole back stretch runs a level higher. Same lengths, so closure is
        // inherited rather than re-earned.
        let pieces: [PieceID] = [
            Catalog.startGrid, Catalog.longStraight, Catalog.longStraight,
            Catalog.curve90TightLeft, Catalog.rampUp, Catalog.curve90TightLeft,
            Catalog.longStraight, Catalog.straight, Catalog.shortStraight,
            Catalog.rampUp, Catalog.gap, Catalog.warp,
            Catalog.curve90TightLeft, Catalog.straight, Catalog.curve90TightLeft,
        ]
        var layout = TrackLayout(pieces: pieces, gateSeams: [0, 6])
        // Two levels down: the lip is at 2 (one ramp to the deck, one to the lip).
        layout.warpDrops = [11: -2]
        // swiftlint:disable:next force_try
        return try! PieceCompiler.compile(layout, id: "elevated-jump-ring")
    }
}
