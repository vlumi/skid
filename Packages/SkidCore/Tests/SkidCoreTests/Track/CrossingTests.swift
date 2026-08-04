import XCTest

@testable import SkidCore

/// At-grade crossings: two stretches of road sharing tarmac at the same height.
///
/// Implicit by design (docs/crossing-plan.md) — nothing is declared, flagged or
/// placed. Steep overlap is legal; shallow overlap stays refused, because that is
/// what keeps the shared zone small enough for kerbs, walls and decals to stay
/// tractable, and what keeps the resolver's heading tiebreak meaningful.
final class CrossingTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    /// The eight built-in, flattened to one level: its bridge crossing becomes an
    /// at-grade crossing at a measured 90°. The acceptance case for the feature.
    private func flattenedEight() throws -> TrackLayout {
        let eight = try TrackCode.decode(
            try XCTUnwrap(TrackLibrary.builtins.first { $0.id == "eight" }).code)
        var flat = eight
        flat.pitches = []
        flat.originHeight = 0
        // The builtin rails its bridge, and flattening turns that bridge into an
        // at-grade crossing — where a railing would wall off the junction the
        // whole fixture exists to test. Railings are per-piece and this fixture
        // wants none, so drop them with the height.
        flat.railed = []
        return flat
    }

    /// **A steep at-grade crossing is legal.** Before this, the flattened eight
    /// was refused as `.overlap` — the only thing keeping the bridgeless figure-8
    /// out of the game.
    func testASteepAtGradeCrossingIsAllowed() throws {
        let flat = try flattenedEight()
        XCTAssertNil(flat.walk().failure)
        XCTAssertFalse(
            TrackValidator.validate(flat).problems.contains(.overlap),
            "a 90° at-grade crossing must be permitted")
    }

    /// And it compiles to a drivable track — the crossing is not merely tolerated
    /// by the validator, it races.
    func testACrossedTrackCompilesAndLaps() throws {
        let flat = try flattenedEight()
        let track = try PieceCompiler.compile(flat, id: "flat-eight")
        XCTAssertGreaterThan(track.centerlineLength, 0)
        XCTAssertFalse(track.gates.isEmpty)

        var race = Race(
            track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
        var driver = AIDriver()
        var ticks = 0
        while race.cars[0].progress.finishedAt == nil, ticks < 120 * Race.tickRate {
            race.advance(
                inputs: [PlayerID(0): driver.input(car: race.cars[0].state, track: track)])
            ticks += 1
        }
        XCTAssertNotNil(
            race.cars[0].progress.finishedAt,
            "the AI must lap a track with an at-grade crossing "
                + "(gate \(race.cars[0].progress.nextGate))")
    }

    /// **A car's progress does not jump at a crossing.** The height tiebreak has
    /// nothing to work with when both roads are at the same level, so without the
    /// heading tiebreak a car in the shared zone resolves onto the road running
    /// across its path — measured at 1606 units of arc in a single tick on this
    /// very track, half the lap, which standings would show as a wild swing.
    /// Laps survive either way (gates are directional), which is exactly why this
    /// needs its own test rather than riding on the lap test.
    func testProgressDoesNotJumpThroughTheCrossing() throws {
        let track = try PieceCompiler.compile(try flattenedEight(), id: "flat-eight")
        var race = Race(
            track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
        var driver = AIDriver()
        func arc() -> Double {
            track.arcPosition(
                of: race.cars[0].state.position,
                preferHeight: race.cars[0].state.height,
                preferHeading: race.cars[0].state.heading)
        }
        var previous = arc()
        var worst = 0.0
        var ticks = 0
        while race.cars[0].progress.finishedAt == nil, ticks < 120 * Race.tickRate {
            race.advance(
                inputs: [PlayerID(0): driver.input(car: race.cars[0].state, track: track)])
            ticks += 1
            let now = arc()
            var moved = abs(now - previous)
            // The lap wraps once, legitimately.
            if moved > track.centerlineLength / 2 {
                moved = track.centerlineLength - moved
            }
            worst = max(worst, moved)
            previous = now
        }
        XCTAssertNotNil(race.cars[0].progress.finishedAt, "it must lap")
        // A tick of driving covers about ten units; anything near a lap fraction
        // is the resolver flipping roads.
        XCTAssertLessThan(
            worst, 100,
            "progress jumped \(Int(worst)) units in one tick — the resolver "
                + "changed roads at the crossing")
    }

    /// **Shallow overlap stays refused.** Two roads running nearly parallel and
    /// touching is not a crossing — it is a merge, or a design mistake, and
    /// permitting it would erase kerbs and edge lines along its whole length.
    func testShallowOverlapIsStillRefused() throws {
        // Four tight 90° turns coil the road back onto itself: measured, the
        // overlapping stretches meet at 3°, which is a merge, not a junction.
        let pieces: [PieceID] = [
            Catalog.startGrid, Catalog.shortStraight, Catalog.curve90TightLeft,
            Catalog.curve90TightLeft, Catalog.curve90TightLeft,
            Catalog.curve90TightLeft,
        ]
        let layout = TrackLayout(pieces: pieces, gateSeams: [0])
        XCTAssertTrue(
            TrackValidator.validate(layout).problems.contains(.overlap),
            "an anti-parallel doubling-back must stay refused")
    }

    /// **A crossing needs equal height, not merely the same spot.** A road
    /// meeting a RAMP at 90° shares no tarmac with it: a ramp is a solid
    /// embankment, so that is driving into a hillside, and the sim's rails make
    /// it undrivable. The angle rule alone permitted it — the height-model
    /// tripwires caught that, which is what they are for.
    func testARoadCrossingARampIsStillRefused() {
        // Start → up → deck → down, then loop back and cross the descending
        // ramp. Same shape as HeightOverlapTests' fixture, which is where this
        // rule's absence was caught; kept here too because it is now a statement
        // about what a "crossing" means, not only about heights.
        var pieces: [PieceID] = [
            Catalog.startGrid, Catalog.rampUp, Catalog.shortStraight,
            Catalog.shortStraight, Catalog.rampDown,
        ]
        pieces += Array(repeating: Catalog.curve45TightLeft, count: 4)  // heading back
        pieces += Array(repeating: Catalog.curve45TightLeft, count: 2)  // turn in
        pieces += [Catalog.shortStraight]  // ...and across the ramp's line
        let layout = TrackLayout(pieces: pieces, gateSeams: [0])
        XCTAssertTrue(
            TrackValidator.validate(layout).problems.contains(.overlap),
            "a road crossing a ramp is an embankment collision, not a junction")
    }

    /// The unflattened eight — a real bridge — is still fine, and still separated
    /// by height rather than by the crossing rule.
    func testTheBridgedEightIsUnaffected() throws {
        let eight = try TrackCode.decode(
            try XCTUnwrap(TrackLibrary.builtins.first { $0.id == "eight" }).code)
        XCTAssertTrue(TrackValidator.validate(eight).isSaveable)
    }

    /// Every built-in still validates: the new permission must not have loosened
    /// anything the existing tracks depend on.
    func testEveryBuiltinStillValidates() throws {
        for builtin in TrackLibrary.builtins {
            let layout = try TrackCode.decode(builtin.code)
            XCTAssertTrue(
                TrackValidator.validate(layout).isSaveable, "\(builtin.id) must stay valid")
        }
    }
}
