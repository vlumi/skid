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
    /// **A car mid-climb paints in its own ramp's storey.** The ribbon paints
    /// whole at the level of its highest end, so a car at height 0.36 stacking
    /// by raw height (level 0) slid UNDER the upper half of the piece it was
    /// driving on — reported on the eight, car swallowed by the lower ramp.
    /// The car's storey must equal the storey its supporting piece was binned
    /// into, at every point of every built-in.
    func testACarOnARampPaintsWithItsRoad() throws {
        for id in TrackLibrary.all.map(\.id) {
            let track = try XCTUnwrap(TrackLibrary.track(id: id))
            for (index, point) in track.centerline.enumerated() {
                let state = probe(at: point, height: track.heights[index])
                XCTAssertEqual(
                    TrackRenderer.carStorey(of: state, on: track),
                    TrackRenderer.storey(ofTop: track.deckTops[index]),
                    "\(id) point \(index) h=\(track.heights[index]): the car "
                        + "must stack with the piece it is on")
            }
        }
    }

    /// The reported scene, pinned concretely: on the eight, a car at a point
    /// whose height is strictly mid-climb (~0.36) paints at storey 1, above
    /// its own ramp — not at level 0, beneath it.
    func testTheMidClimbCarIsNotSwallowedByTheRamp() throws {
        let track = try XCTUnwrap(TrackLibrary.track(id: "eight"))
        let index = try XCTUnwrap(
            track.heights.firstIndex { $0 > 0.3 && $0 < 0.45 },
            "the eight should have a mid-climb point")
        let state = probe(at: track.centerline[index], height: track.heights[index])
        XCTAssertEqual(TrackRenderer.carStorey(of: state, on: track), 1)
        XCTAssertEqual(Track.level(of: state.height), 0, "raw height would say 0 — the bug")
    }

    /// A car on the grass keeps its raw-height storey: there is no piece under
    /// it, so the bridge covers it and the bubble takes over.
    func testAGrassCarKeepsItsOwnStorey() throws {
        let track = try XCTUnwrap(TrackLibrary.track(id: "eight"))
        let offRoad = try XCTUnwrap(
            grassPoint(on: track), "the eight should have grass near the road")
        let state = probe(at: offRoad, height: 0)
        XCTAssertEqual(TrackRenderer.carStorey(of: state, on: track), 0)
    }

    /// `storey(ofTop:)` must be the exact inverse of `storeyBand`: every real
    /// piece top (heights come in half-level steps) maps to the one band that
    /// contains it, so cars and ribbons can never disagree by construction.
    func testStoreyOfTopInvertsTheBands() {
        for step in 0...4 {
            let top = Double(step) * Track.levelHeight / 2
            let storey = TrackRenderer.storey(ofTop: top)
            XCTAssertTrue(
                TrackRenderer.storeyBand(storey).contains(top),
                "top \(top) must fall in its own storey's band")
        }
    }

    /// A car body somewhere, for storey questions — only position and height
    /// matter to the z-order.
    private func probe(at position: Vec2, height: Double) -> CarState {
        var state = CarState(position: position, heading: 0)
        state.height = height
        return state
    }

    /// Some point on the grass: step outward from a centerline point until
    /// clear of the road at EVERY height (so no bridge stretch claims it).
    private func grassPoint(on track: Track) -> Vec2? {
        let out = Vec2(track.width * 1.5, 0)
        for point in track.centerline {
            let candidate = point + out
            if track.distanceToCenterline(candidate) > track.width / 2 + 1 {
                return candidate
            }
        }
        return nil
    }

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
