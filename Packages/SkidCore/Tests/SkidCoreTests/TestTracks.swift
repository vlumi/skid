import Foundation

@testable import SkidCore

/// Fixtures owned by the tests, for properties the shipping built-ins no
/// longer guarantee. The eight used to double as "a track with a steep ramp";
/// when it was rebuilt from gentle pitched sweeps, every test that scavenged
/// it for steepness lost its fixture — so the steep bridge lives here instead,
/// immune to built-in redesigns.
enum TestTracks {
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
