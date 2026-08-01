import XCTest

@testable import SkidCore

/// The checked-in built-in codes, and the cap rule that a multi-piece deck
/// exposed.
final class BuiltinCodeTests: XCTestCase {
    /// A code in source must be **canonical**: decoding and re-encoding it has to
    /// give the same string back. Codes double as track identity, so a code that
    /// isn't a fixed point means one track could be named two ways.
    ///
    /// Also asserts every layout piece is primitive — the pieces section packs into
    /// compounds for the bytes, but a decoded layout is always primitives, and a
    /// compound leaking into one would put seam indices out of step.
    func testBuiltinCodesAreCanonicalPrimitiveLayouts() throws {
        for builtin in TrackLibrary.builtins {
            let layout = try TrackCode.decode(builtin.code)
            XCTAssertEqual(
                TrackCode.encode(layout), builtin.code,
                "\(builtin.id): re-encoding changed the code, so it isn't canonical")
            for piece in layout.pieces {
                XCTAssertTrue(
                    PieceExpansion.isPrimitive(piece),
                    "\(builtin.id): layout holds compound piece \(piece)")
            }
            XCTAssertLessThanOrEqual(layout.pieces.count, TrackCode.maxLength)
        }
    }

    /// **Every built-in is lappable by the AI.** A shipped track that the AI
    /// can't complete is broken for single-player and for filling a grid, and
    /// the raised-baseline clover is exactly the kind of track where height
    /// handling could silently strand it.
    func testEveryBuiltinIsLappableByTheAI() {
        for track in TrackLibrary.all {
            var race = Race(
                track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
            var driver = AIDriver()
            var ticks = 0
            while race.cars[0].progress.finishedAt == nil, ticks < 120 * Race.tickRate {
                race.advance(
                    inputs: [PlayerID(0): driver.input(car: race.cars[0].state, track: track)])
                ticks += 1
            }
            let progress = race.cars[0].progress
            XCTAssertNotNil(
                progress.finishedAt,
                "AI never lapped \(track.id) (gate \(progress.nextGate), lap \(progress.lap))")
        }
    }

    /// **One cap per ramp, and none on the deck between them.**
    ///
    /// The under-deck cap seals the open air beneath a ramp's raised end. It is a
    /// property of the elevated RUN, but it used to be emitted per piece, from
    /// whichever of that piece's ends sampled higher. A flat deck piece has both
    /// ends at deck height, so it claimed a "high end" too and dropped a cap
    /// across the middle of the bridge — and since a cap at 0.9 has floor
    /// `trunc(0.9)` = 0, it blocked the road running underneath.
    ///
    /// The old catalog hid this: a 2U deck was one piece, so there was no seam to
    /// go wrong. With a primitive layout that deck is two short straights and the
    /// fault appears, which is why this is pinned by count.
    func testTheDeckBetweenRampsCarriesNoCap() throws {
        let track = TrackLibrary.track(id: "eight")
        let caps = track.walls.filter { $0.kind == .gate }
        // Two per full climb since the half-height lattice: the apex seal
        // (mouth of the lower half, at 0.3) and the deck seal (0.8).
        XCTAssertEqual(caps.count, 4, "expected two gates per full climb")

        // And the decisive part: no cap may block the ground road under the bridge.
        for cap in caps {
            for index in track.centerline.indices where track.height(ofSegment: index) < 0.1 {
                let point = track.centerline[index]
                let distance = point.closestPoint(onSegment: cap.a, cap.b).distance(to: point)
                XCTAssertGreaterThan(
                    distance, CarGeometry.radius,
                    "a cap sits on the ground road at centerline \(index)")
            }
        }
    }

    /// Deck gets side rails but no cap; a ramp gets both. Stated against the
    /// predicate itself so the rule is pinned independently of any one track.
    ///
    /// A deck piece is an ordinary straight or corner sitting at height 1 — same
    /// ids as on the ground — so what marks a ramp is the piece's own
    /// `heightDelta`, not anything about where it happens to be.
    func testOnlyARampOwnsAHighEnd() throws {
        let layout = try XCTUnwrap(TrackLibrary.layout(id: "eight"))
        let placed = layout.walk().placed
        let elevated = placed.filter { $0.entryHeight > 0.5 || $0.exitHeight > 0.5 }
        XCTAssertFalse(elevated.isEmpty, "the eight should have an elevated run")
        for piece in elevated {
            XCTAssertEqual(
                PieceCompiler.capsHighEnd(piece), piece.climb != 0,
                "only a climbing placement caps; deck pieces are ordinary road")
        }
        // And the deck really is built from the same ids used on the ground.
        let deck = elevated.filter { $0.climb == 0 }
        XCTAssertFalse(deck.isEmpty, "the eight should have level deck")
        for piece in deck {
            XCTAssertTrue(
                PieceExpansion.isPrimitive(piece.id),
                "deck piece \(piece.id) should be an ordinary primitive")
        }
    }
}
