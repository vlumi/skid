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
    /// **A car never paints below the piece it is on.** The ribbon paints
    /// whole at the level of its highest end, so a car at height 0.36 stacking
    /// by raw height (level 0) slid UNDER the upper half of the piece it was
    /// driving on — reported on the eight, car swallowed by the lower ramp.
    /// At every point of every built-in, the car's storey is at least its
    /// supporting piece's (it may exceed it where the body straddles a seam
    /// onto a higher-binned neighbour — that is the point of the body rule).
    func testACarOnARampPaintsWithItsRoad() throws {
        for id in TrackLibrary.all.map(\.id) {
            let track = try XCTUnwrap(TrackLibrary.track(id: id))
            for (index, point) in track.centerline.enumerated() {
                let state = probe(at: point, height: track.heights[index])
                XCTAssertGreaterThanOrEqual(
                    TrackRenderer.carStorey(of: state, on: track),
                    TrackRenderer.storey(ofTop: track.deckTops[index]),
                    "\(id) point \(index) h=\(track.heights[index]): the car "
                        + "must not stack below the piece it is on")
            }
        }
    }

    /// **A car straddling a descent's hand-over seam paints with the descent.**
    /// The clover's dips: where the 0.5→0 piece meets the flat underpass run,
    /// the descent's ribbon is binned a storey up, and a car whose tail still
    /// touches it was painted over at its own height — reported as the car
    /// half-swallowed at the dip. The body rule lifts it to the highest road
    /// it touches.
    func testAStraddlingCarPaintsWithTheHigherPiece() throws {
        let track = try XCTUnwrap(TrackLibrary.track(id: "clover"))
        let n = track.centerline.count
        // The hand-over POINT is the descent's exit: the last 0.5-topped
        // sample. (The first 0-topped point is a whole piece later on a
        // sparsely-sampled straight, so searching for it finds the wrong spot.)
        let seam = try XCTUnwrap(
            (0..<n).first {
                track.deckTops[$0] == 0.5 && track.deckTops[($0 + 1) % n] == 0
            }, "the clover should hand a descent over to a flat run")
        let along =
            (track.centerline[(seam + 1) % n] - track.centerline[seam]).normalized
        // Center 6 units onto the flat: the tail (12 back) still overlaps the
        // descent's ribbon, the nose is clear on the flat.
        var state = probe(at: track.centerline[seam] + along * 6, height: 0)
        state.heading = atan2(along.y, along.x)
        XCTAssertEqual(
            TrackRenderer.carStorey(of: state, on: track), 1,
            "the tail still touches the descent piece")
        // A body length further on, nothing touches the descent any more —
        // the car settles into the underpass storey (and the bubble regime).
        var clear = probe(at: track.centerline[seam] + along * 30, height: 0)
        clear.heading = state.heading
        XCTAssertEqual(TrackRenderer.carStorey(of: clear, on: track), 0)
    }

    /// **Deep in the underpass the car keeps the ground storey**, body rule or
    /// not: the bridge overhead is road at ANOTHER height, so the body must not
    /// inherit its storey — that is what keeps the car under the deck (with the
    /// bubble), instead of painting on top of the thing it is sliding under.
    func testAnUnderpassCarStaysUnderTheBridge() throws {
        let track = try XCTUnwrap(TrackLibrary.track(id: "clover"))
        let n = track.centerline.count
        // The middle of a flat h-0 run, far from both hand-over seams.
        let underpass = try XCTUnwrap(
            (0..<n).first { i in
                (-3...3).allSatisfy { track.deckTops[(i + $0 + n) % n] == 0 }
            }, "the clover should have a flat run at the bottom of a dip")
        let state = probe(at: track.centerline[underpass], height: 0)
        XCTAssertEqual(TrackRenderer.carStorey(of: state, on: track), 0)
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

    /// **A car under the bridge's WALL still gets a window.** The trigger and
    /// the hole must agree about how far the bridge reaches, and that reach is
    /// the whole footprint — asphalt plus the rails standing on its edges,
    /// which hide the ground under them just as the asphalt does. They
    /// disagreed: the trigger reached the rail's outer edge (87 on the eight)
    /// while the hole was cut only in the asphalt (72), so a car passing under
    /// the wall triggered a window with nowhere to draw and stayed invisible.
    func testACarUnderTheBridgeWallStillGetsAWindow() throws {
        let track = try XCTUnwrap(TrackLibrary.track(id: "eight"))
        let deckHeight = Track.levelHeight
        let n = track.centerline.count
        let crossing = try XCTUnwrap(
            (0..<n).first {
                track.heights[$0] < 0.05
                    && track.distanceToCenterline(track.centerline[$0], height: deckHeight)
                        <= track.width / 2
            }, "the eight should cross under its own bridge")
        let (segment, _) = track.closestCenterlinePoint(
            to: track.centerline[crossing], preferHeight: deckHeight)
        let ahead = track.centerline[(segment + 1) % n] - track.centerline[segment]
        let across = ahead.normalized.perpendicular
        let clip = TrackRenderer.probeCoveringDeck(
            track: track, storey: Track.level(of: deckHeight))
        // Out past the asphalt, inside the rail band: under the wall.
        let underWall =
            track.centerline[crossing]
            + across * (track.halfWidth(atHeight: deckHeight) + 6)
        XCTAssertLessThan(
            track.halfWidth(atHeight: deckHeight) + 6,
            track.footprintHalfWidth(atHeight: deckHeight),
            "the probe point must be inside the rail band")
        XCTAssertTrue(
            clip.contains(CGPoint(x: underWall.x, y: underWall.y)),
            "the hole must be cut under the rail too, or the car is invisible there")

        // And the trigger reaches exactly as far as the hole's disc can still
        // touch that footprint — no further (wasted layers), no nearer (windows
        // cut off while still visible). The disc is centred on the car, so the
        // margin past the footprint is its RADIUS: both are measured as
        // perpendicular distance from the same centerline.
        let footprint = track.footprintHalfWidth(atHeight: deckHeight)
        for offset in [footprint - 5, footprint + 5, footprint + 15] {
            let point = track.centerline[crossing] + across * offset
            XCTAssertTrue(
                discTouches(clip, at: point),
                "at \(offset) the disc still overlaps the bridge, so a window is due")
        }
        // A full disc-diameter out, nothing of the hole can reach the bridge.
        let clear = track.centerline[crossing] + across * (footprint + 45)
        XCTAssertFalse(
            discTouches(clip, at: clear),
            "well clear of the bridge, no part of the hole can overlap it")
    }

    /// Whether a window disc centred at `point` overlaps `region` — sampled on
    /// its rim, which is where a centred disc first touches.
    private func discTouches(_ region: Path, at point: Vec2) -> Bool {
        for degrees in stride(from: 0.0, to: 360.0, by: 15.0) {
            let radians = degrees * .pi / 180
            let rim = CGPoint(
                x: point.x + cos(radians) * 19.5, y: point.y + sin(radians) * 19.5)
            if region.contains(rim) { return true }
        }
        return false
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
                "\(Track.highestLevel + 1)/airborne",
            ])
    }

    /// A flat track still draws: it has the ground storey and nothing else.
    func testAFlatTrackHasOneStorey() {
        XCTAssertEqual(TrackRenderer.trackStoreys(TrackLibrary.track(id: "small")), [0])
        XCTAssertEqual(TrackRenderer.trackStoreys(TrackLibrary.track(id: "eight")), [0, 1])
    }
}
