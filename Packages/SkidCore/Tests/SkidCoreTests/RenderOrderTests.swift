import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// The z-order that replaced two hardcoded height passes. What matters is that
/// storey and kind alone decide what covers what — no drawable needs a rule of
/// its own, and no case can fall between two passes.
final class RenderOrderTests: XCTestCase {
    /// **The rule, stated once:** lower storeys paint first, and within a
    /// storey the kinds paint in a fixed order — so a car is over its own road
    /// and under any road a level above it.
    func testSortIsStoreyThenKindThenInsertion() {
        let deckRoad = RenderOrder.Layer(storey: 1, kind: .road, sequence: 0) { _ in }
        let groundCar = RenderOrder.Layer(storey: 0, kind: .car, sequence: 1) { _ in }
        let deckCar = RenderOrder.Layer(storey: 1, kind: .car, sequence: 2) { _ in }
        let groundRoad = RenderOrder.Layer(storey: 0, kind: .road, sequence: 3) { _ in }
        let sorted = [deckRoad, groundCar, deckCar, groundRoad].sorted()
        XCTAssertEqual(
            sorted.map { ($0.storey, $0.kind) }.map { "\($0.0)/\($0.1)" },
            ["0/road", "0/car", "1/road", "1/car"],
            "lower storeys first; within a storey, road before car")
    }

    /// Insertion order survives inside one `(storey, kind)` group — ribbons
    /// must keep walk order, cars player order.
    func testInsertionOrderIsStableWithinAGroup() {
        let layers = (0..<5).reversed().map {
            RenderOrder.Layer(storey: 0, kind: .car, sequence: $0) { _ in }
        }
        XCTAssertEqual(
            layers.sorted().map(\.sequence), [0, 1, 2, 3, 4],
            "a group paints in the order it was collected")
    }

    /// **A car on the GRASS under a bridge is covered by it.** This is the bug
    /// the z-order subsumes: the old rule asked whether the car stood on
    /// ground-height *road*, and grass answered "no road here" — the same
    /// answer as "road above me" — so an off-ribbon car under a deck drew on
    /// top of it. Storey doesn't consult the road at all.
    func testAGrassCarUnderTheBridgeIsCoveredByIt() throws {
        let track = TrackLibrary.track(id: "eight")
        let deckIndex = try XCTUnwrap(track.centerline.indices.first { track.heights[$0] > 0.9 })
        let grass = try XCTUnwrap(
            [80.0, -80.0, 100.0, -100.0]
                .map { track.centerline[deckIndex] + Vec2(1, 0) * $0 }
                .first { track.surface(at: $0, height: 0) == .grass },
            "the eight should have grass beside its deck")
        XCTAssertEqual(track.surface(at: grass, height: 0), .grass)
        // The car is at height 0 out there, so it belongs to storey 0 — under
        // the deck's storey 1, whatever the surface beneath it happens to be.
        XCTAssertLessThan(Track.level(of: 0), Track.level(of: 1))
    }

    /// Every storey the track uses gets its own road band, and the bands
    /// partition: a piece belongs to exactly one, by its highest end. In two
    /// bands is a double-draw that buries whatever sits between them; in
    /// neither is a hole in the road.
    func testStoreyBandsPartitionEveryPiece() throws {
        for id in ["small", "oval", "eight", "clover"] {
            let layout = try XCTUnwrap(TrackLibrary.layout(id: id))
            let bands = TrackRenderer.trackStoreys(TrackLibrary.track(id: id))
                .map(TrackRenderer.storeyBand)
            for piece in layout.walk().placed {
                let top = max(piece.entryHeight, piece.exitHeight)
                let hits = bands.filter { $0.contains(top) }.count
                XCTAssertEqual(hits, 1, "\(id): a piece topping at \(top) hit \(hits) bands")
            }
        }
    }

    /// **The whole paint order for a bridged track**, pinned as a list. This is
    /// the sequence the two-pass code produced by hand — ground road, its
    /// marks, its gates, its cars, then the same for the deck, airborne last —
    /// so the rewrite is behaviour-preserving where behaviour was already right.
    func testThePaintOrderForABridgedTrack() {
        let track = TrackLibrary.track(id: "eight")
        var order = RenderOrder.Builder()
        for storey in TrackRenderer.trackStoreys(track) {
            order.add(storey: storey, kind: .road) { _ in }
            order.add(storey: storey, kind: .gate) { _ in }
            order.add(storey: storey, kind: .mark) { _ in }
        }
        order.add(storey: 0, kind: .ground) { _ in }
        order.add(height: 0, kind: .car) { _ in }
        order.add(height: 1, kind: .car) { _ in }
        order.add(storey: Track.highestLevel + 1, kind: .airborne) { _ in }
        XCTAssertEqual(
            order.debugOrder,
            [
                "0/ground", "0/road", "0/mark", "0/gate", "0/car",
                "1/road", "1/mark", "1/gate", "1/car",
                "2/airborne",
            ])
    }

    /// A flat track still draws: it has the ground storey and nothing else.
    func testAFlatTrackHasOneStorey() {
        XCTAssertEqual(TrackRenderer.trackStoreys(TrackLibrary.track(id: "small")), [0])
        XCTAssertEqual(TrackRenderer.trackStoreys(TrackLibrary.track(id: "eight")), [0, 1])
    }
}
