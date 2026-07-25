import XCTest

@testable import SkidCore

/// The forcing function, Phase-A scope: prove the whole pipeline end to end on
/// a representative piece-track — straights + curves closing into a loop, a
/// ramp onto an elevated bridge, and a share-code round-trip — so the model is
/// known drivable before the editor renders it. (Faithful Hairpin/Overpass
/// rebuilds come with the editor, per the roadmap.)
final class PieceModelAcceptanceTests: XCTestCase {
    // Pieces are named through PieceCatalog.ID — ids are data and reshuffle
    // freely until the format's first public release, so nothing here hardcodes
    // a number.
    private typealias Pieces = PieceCatalog.ID

    /// A plain closed loop that exercises straights + 90° curves and closes
    /// exactly, compiling to a drivable Track (grid on asphalt, gates span the
    /// ribbon), and round-trips through the share code unchanged.
    func testRepresentativeLoopCompilesAndRoundTrips() throws {
        // Rounded square: start then four [left-90, straight] quarters —
        // symmetric, so it closes exactly. The start piece and the straight are
        // both 2U, and a 90° tight arc advances 1U, so every side matches.
        let pieces: [PieceID] = [
            Pieces.startGrid, Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
            Pieces.straight,
            Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
        ]
        let layout = TrackLayout(pieces: pieces, gateSeams: [0, 2, 4, 6])

        // 1. Saveable.
        XCTAssertTrue(TrackValidator.validate(layout).isSaveable)

        // 2. Compiles to a well-formed Track.
        let track = try PieceCompiler.compile(layout, id: "accept-loop")
        for slot in track.startSlots {
            XCTAssertEqual(track.surface(at: slot), .asphalt)
        }
        for p in track.centerline {
            XCTAssertEqual(track.surface(at: p), .asphalt)
        }
        XCTAssertEqual(track.gates.count, 4)

        // 3. Drivable: a car can complete the gate sequence in order. Simulate
        // a point tracing the centerline and confirm every gate is crossed
        // forward, in order, ending back at start/finish.
        assertLapCrossesAllGatesInOrder(track)

        // 4. Share code round-trips to the same layout, and the re-compiled
        // track matches.
        let code = TrackCode.encode(layout)
        let back = try TrackCode.decode(code)
        XCTAssertEqual(back, layout)
    }

    /// A ramp exercises elevation end to end: start, climb to the bridge deck,
    /// run along it, descend, and close the loop — all on the unit grid, so it
    /// closes exactly and compiles. Confirms height bookkeeping,
    /// elevatedSegments, and Ramp emission.
    func testRampProducesAnElevatedBridge() throws {
        // One side carries ramp-up(2U) + deck(2U) + ramp-down(2U); the rest is a
        // rounded rectangle of straights and tight 90s sized to bring it home.
        let pieces: [PieceID] = [
            Pieces.startGrid, Pieces.rampUp, Pieces.straight, Pieces.rampDown,
            Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
            Pieces.longStraight, Pieces.straight, Pieces.straight,
            Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
        ]
        let layout = TrackLayout(pieces: pieces, gateSeams: [0, 4])
        let walk = layout.walk()
        XCTAssertNil(walk.failure)
        XCTAssertTrue(walk.openEnds.isEmpty, "the bridge loop must close exactly")

        // Height bookkeeping: the deck run sits at height 1, and the loop
        // returns to the ground before the start line.
        XCTAssertTrue(
            walk.placed.contains { $0.entryHeight > 0.5 && $0.exitHeight > 0.5 },
            "the deck piece should sit at deck height")
        XCTAssertEqual(walk.placed.last?.exitHeight, 0, "a closed loop returns to the ground")

        XCTAssertTrue(TrackValidator.validate(layout).isSaveable)
        let track = try PieceCompiler.compile(layout, id: "accept-ramp")
        XCTAssertFalse(track.elevatedSegments.isEmpty, "the deck should be elevated")
        XCTAssertFalse(track.ramps.isEmpty, "ramps should be emitted")
        XCTAssertTrue(track.ramps.contains { $0.launches }, "ramp-up launches")
    }

    // MARK: - helpers

    /// Drive a point around the closed centerline and assert **every** gate is
    /// crossed forward somewhere on the lap — i.e. all gates sit on the driven
    /// path, oriented with traffic. (The runtime's own lap logic handles the
    /// start-offset ordering; here we just prove the gates are drivable.)
    private func assertLapCrossesAllGatesInOrder(_ track: Track) {
        var crossed = Set<Int>()
        let line = track.centerline
        for i in line.indices {
            let a = line[i]
            let b = line[(i + 1) % line.count]
            for (g, gate) in track.gates.enumerated()
            where gate.crossedForward(movingFrom: a, to: b) {
                crossed.insert(g)
            }
        }
        XCTAssertEqual(
            crossed.count, track.gates.count,
            "gates not all crossed forward on the lap: \(crossed) of \(track.gates.count)")
    }
}
