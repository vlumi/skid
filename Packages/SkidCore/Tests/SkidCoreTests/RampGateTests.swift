import XCTest

@testable import SkidCore

/// The gate under a ramp's mouth admits cars of its level and blocks the rest —
/// which couples it to the climb physics: a flat-out climber must ARRIVE above
/// the threshold. These tests pin that coupling for every ramp in the catalog,
/// so a steeper future ramp (a tight curved one, say) or a slower climb clamp
/// fails here instead of on a device.
/// A ramp piece and its measured centerline length.
private struct CatalogRamp {
    var id: PieceID
    var piece: Piece
    var arc: Double
}

final class RampGateTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    /// Every ramp in the catalog, with its centerline length.
    private func catalogRamps() -> [CatalogRamp] {
        PieceCatalog.all
            .filter { $0.value.heightDelta != 0 }
            .map { id, piece in
                let placed = PlacedPiece(
                    id: id, piece: piece, entry: .origin,
                    exits: [piece.paths[0].exit(from: .origin)], entryHeight: 0, entrySeam: 0)
                let points = placed.centerlineSamples(degreesPerSample: 6)
                var arc = 0.0
                for step in 1..<points.count {
                    arc += points[step].distance(to: points[step - 1])
                }
                return CatalogRamp(id: id, piece: piece, arc: arc)
            }
    }

    /// **Analytic:** the worst-case climber — top speed the whole way — must
    /// arrive at the mouth above the gate, with margin. This is the inequality
    /// the gate's placement depends on, stated as arithmetic so it can't drift
    /// silently: height gained = (arc / distance-per-tick) · climb-per-tick.
    func testEveryRampOutclimbsItsOwnGate() {
        let perTick = CarTuning().maxSpeed * Race.dt
        for ramp in catalogRamps() {
            let ticks = ramp.arc / perTick
            let arrival = min(Track.levelHeight, ticks * Race.maxHeightChangePerTick)
            let threshold = Track.levelHeight - Track.reachTolerance
            XCTAssertGreaterThanOrEqual(
                arrival, threshold + 0.05,
                "ramp \(ramp.id) (\(Int(ramp.arc)) units) climbs to \(arrival) flat out, "
                    + "too close to its own gate at \(threshold) — longer ramp or "
                    + "gentler slope needed")
        }
    }

    /// **Behavioural:** actually drive it. A car at full speed and full throttle
    /// runs straight over up-ramp, deck, and down-ramp; it must touch nothing,
    /// genuinely climb, and come back down. Full speed is the worst case (fewest
    /// ticks on the slope), and full throttle keeps it there — a coasting car
    /// proves nothing, which is a trap this suite has fallen into before.
    func testAFlatOutCarClearsEveryRampPairing() throws {
        let ups = catalogRamps().filter { $0.piece.heightDelta > 0 }
        let downs = catalogRamps().filter { $0.piece.heightDelta < 0 }
        XCTAssertFalse(ups.isEmpty)
        for up in ups {
            for down in downs {
                try driveOver(up: up.id, down: down.id)
            }
        }
    }

    /// Build start → up → deck → down plus a rectangle back to the start entry,
    /// and drive the straight through the ramps at full speed.
    private func driveOver(up: PieceID, down: PieceID) throws {
        var pieces: [PieceID] = [
            Pieces.startGrid, up, Pieces.shortStraight, Pieces.shortStraight, down,
        ]
        let walked = TrackLayout(pieces: pieces, gateSeams: [0]).walk()
        let end = try XCTUnwrap(walked.placed.last?.exits.first)
        // The rectangle closer assumes the loose end still runs along the start
        // axis; a future curved ramp will need its own fixture here.
        guard end.heading == walked.placed[0].entry.heading else {
            XCTFail("ramp pair \(up)/\(down) bends the road — give it a fixture")
            return
        }
        let run = Int(end.position.vec2.x.rounded()) / PieceCatalog.shortStraight
        pieces += Array(repeating: Pieces.curve45TightLeft, count: 4)
        pieces += Array(repeating: Pieces.shortStraight, count: run)
        pieces += Array(repeating: Pieces.curve45TightLeft, count: 4)
        let layout = TrackLayout(pieces: pieces, gateSeams: [0, 5])
        let track = try PieceCompiler.compile(layout, id: "gate-\(up)-\(down)")

        var race = Race(track: track, players: [PlayerID(0)])
        race.cars[0].state.velocity = Vec2(race.tuning.maxSpeed, 0)
        var peak = 0.0
        // The compiler re-frames geometry to its own footprint, so the ramp
        // exit's world x needs the same shift the track's points got.
        let goal = end.position.vec2.x + track.layoutOffset.x
        for _ in 0..<240 {
            race.advance(inputs: [PlayerID(0): CarInput(throttle: 1)])
            let car = race.cars[0].state
            peak = max(peak, car.height)
            for event in race.lastEvents {
                if case .wallImpact = event {
                    XCTFail("flat-out car hit a wall on ramp pair \(up)/\(down) at h=\(car.height)")
                    return
                }
            }
            if car.position.x > goal + 60 {
                XCTAssertGreaterThan(peak, 0.95, "never actually climbed (\(up)/\(down))")
                XCTAssertLessThan(car.height, 0.1, "never came back down (\(up)/\(down))")
                return
            }
        }
        XCTFail("car never made it past the descent on ramp pair \(up)/\(down)")
    }
}
