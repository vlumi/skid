import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Which bank a tire mark lands in decides which roads can paint over it.**
///
/// Ground marks draw under every elevated ribbon; elevated marks draw after it. The
/// split must follow the storey the road PAINTS at — the raw-height rule put a mark
/// laid at a climbing ramp's low beginning (car still at ground height, ribbon painting
/// a level up) into the ground bank, where the ramp's own asphalt covered it. Reported
/// from device: tire marks stop dead at the beginning of a ramp.
final class MarkStoreTests: XCTestCase {
    /// Slide a car sideways at `position` on `track` for two recorded ticks, so the
    /// store has a previous tire set and lays segments on the second call.
    private func slide(at position: Vec2, on track: Track, store: inout MarkStore) {
        let height = track.height(at: position)
        var car = Car(
            id: PlayerID(0),
            state: CarState(position: position, velocity: Vec2(0, 300), height: height))
        store.record(car: car, on: track, tick: 0)
        car.state.position += Vec2(0, 12)
        car.state.height = track.height(at: car.state.position)
        store.record(car: car, on: track, tick: 2)
    }

    private func segments(in bank: [MarkStore.Bucket: [MarkStore.Chunk]]) -> Int {
        bank.values.flatMap { $0 }.reduce(0) { $0 + $1.count }
    }

    /// On flat ground, rubber lands in the ground bank — under any bridge's paint.
    func testGroundRubberLandsInTheGroundBank() {
        let track = Track(
            centerline: [Vec2(0, -400), Vec2(0, 400)],
            width: 120, size: Vec2(2_000, 2_000))
        var store = MarkStore()
        slide(at: Vec2(0, 0), on: track, store: &store)
        XCTAssertGreaterThan(segments(in: store.chunks), 0)
        XCTAssertEqual(segments(in: store.elevatedChunks), 0)
    }

    /// **At a climbing ramp's low beginning the car is still at ground height, but
    /// its road paints a storey up** — the mark must follow the road, or the ramp's
    /// own asphalt covers it. The reported bug, pinned.
    func testMarksOnARampsLowBeginningFollowTheRampsStorey() {
        // One segment climbing 0 → 1: it paints at the storey of its highest end.
        let track = Track(
            centerline: [Vec2(0, -400), Vec2(0, 400)],
            width: 120, heights: [0, 1], size: Vec2(2_000, 2_000))
        let toe = Vec2(0, -390)
        XCTAssertLessThanOrEqual(
            track.height(at: toe), Track.surfaceTolerance,
            "the fixture must slide at ground height, where the old rule failed")
        var store = MarkStore()
        slide(at: toe, on: track, store: &store)
        XCTAssertEqual(
            segments(in: store.chunks), 0,
            "a ground-bank mark here is painted over by the ramp's own ribbon")
        XCTAssertGreaterThan(segments(in: store.elevatedChunks), 0)
    }
}
