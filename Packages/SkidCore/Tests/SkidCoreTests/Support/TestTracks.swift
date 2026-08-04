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
