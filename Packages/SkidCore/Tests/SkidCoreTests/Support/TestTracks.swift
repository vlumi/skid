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
        /// run close enough that the gate corridor's neighbour-lane cap bites —
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
            "AXABFR95BAQQAQMDDwEDAw8BegQEBAQEBAIFAAQKFBoDBQLQAtAA_iDUVapunfF_mc99V8r_"
            + "weRH0rknUHfADJley31chwDYnP9AQfgQ4hdOAJFdIXX09sTndJh4oKgxKWYkC75k871YA4"
            + "AL-966tuPFpBJQ1hrXKNYRNBrSRvttD-6JsjOz7F5xCg"
        /// The reported "tower of babel": road at all four storeys, fully railed,
        /// with decks stacked over one another. The hard case for the see-through
        /// window — a car may be one, two OR three storeys below a road.
        static let towerOfBabel =
            "AbcBFR95BAQQAQMDDwEDAw8BegQEBAQEBAIFAAQKFBoDBQLQAtAACB8AAQIDBAUGBwgJCgsM"
            + "DQ4PEBESExQVFhcYGRobHB0e_iDUVapunfF_mc99V8r_weRH0rknUHfADJley31chwDYnP"
            + "9AKyj2tjZTDQTf-XN6GJZCG7iVZP0-2QMsh5woK_pYFxgVtMuW2gjO6qgh8Qq4DUuFcH1J"
            + "a81GR5jaxV2VUjrMDw"
        static let bridgeRing = "Ad0BDh8KDBEFeQUFFXoGBHgEAgQABAgMAwUC0ADwAAgGCgsMDQ4P"
        /// The clover: 47 pieces, closed, three gates, two crossings.
        static let clover = "AQ4BGR8eAQ95AwMBHgEPAwMBHgEPAwMBHgEPAwMCAwAXIwMFBLAFoAAFAQI"
        /// The clover mid-build: 46 pieces, still open at both ends.
        static let cloverOpen = "ASEBGh8PeQMDAR4BDwMDAR4BDwMDAR4BDwMDAXoAAgEAAwUAAAAAAA"
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
}
