import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The see-through window: a car under road still shows.**
///
/// Split from `Level3Tests` to keep that class inside its length budget — the window
/// is its own subject, and it took three attempts across as many storey counts.
@MainActor
final class UnderDeckWindowTests: XCTestCase {
    /// **A car hidden under a high deck still shows through it.**
    ///
    /// The never-invisible rule cut its window at `storey + 1` — the only candidate
    /// when there was one deck. With three, a ground car under a level-3 bridge
    /// asked about storey 1, found no road overhead there, and got no window at all:
    /// hidden, with nothing to see it through.
    ///
    /// Asserted through `addCars` and `debugOrder`, i.e. the real code path. A first
    /// version re-derived the scan with `stride` inside the test and passed against
    /// every sabotage — including a revert to `storey + 1`.
    func testAGroundCarUnderAHighDeckGetsAWindow() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.threeStorey), id: "l3")
        // A ground point under a deck two storeys up, with no road at storey 1.
        let spot = try XCTUnwrap(
            track.centerline.indices.first { index in
                guard Track.level(of: track.heights[index]) >= 2 else { return false }
                let point = track.centerline[index]
                return !track.centerline.indices.contains { other in
                    Track.level(of: track.heights[other]) == 1
                        && (track.centerline[other] - point).length
                            < track.footprintHalfWidth(atHeight: 1)
                }
            }, "the fixture must have road high above bare ground")
        let point = track.centerline[spot]

        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
        race.cars[0].state.position = point
        race.cars[0].state.height = 0
        var order = RenderOrder.Builder()
        TrackRenderer.addCars(
            scene: scene(race), gateChrome: chrome(for: track),
            colorAt: { _ in .red }, to: &order)
        let windows = order.debugOrder.filter { $0.hasSuffix("/window") }
        XCTAssertFalse(
            windows.isEmpty,
            "a ground car under a storey-\(Track.level(of: track.heights[spot])) deck must "
                + "get a window; got \(order.debugOrder)")
    }

    /// **Every storey under every road, on a track that uses all of them.**
    ///
    /// The reported "tower of babel" has road at all four storeys with decks stacked
    /// over one another, so a car can be one, two or three storeys below a road —
    /// the case a `storey + 1` scan could only ever get right by luck.
    func testEveryStoreyUnderEveryRoadGetsAWindow() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.towerOfBabel), id: "babel")
        XCTAssertEqual(
            Set(track.heights.map { Track.level(of: $0) }), Set(0...Track.highestLevel),
            "the fixture must use every storey")
        var checked = 0
        for index in track.centerline.indices where track.heights[index] > 0.5 {
            let point = track.centerline[index]
            let roadStorey = Track.level(of: track.heights[index])
            for carStorey in 0..<roadStorey {
                var race = Race(
                    track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
                race.cars[0].state.position = point
                race.cars[0].state.height = Double(carStorey)
                var order = RenderOrder.Builder()
                TrackRenderer.addCars(
                    scene: scene(race), gateChrome: chrome(for: track),
                    colorAt: { _ in .red }, to: &order)
                XCTAssertFalse(
                    order.debugOrder.filter { $0.hasSuffix("/window") }.isEmpty,
                    "a car on storey \(carStorey) under storey-\(roadStorey) road at "
                        + "\(point) must show through it")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 100, "the sweep must actually cover the track")
    }

    /// And a car in the open gets none — the window is for a car that would
    /// otherwise be invisible, not decoration.
    func testACarInTheOpenGetsNoWindow() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.threeStorey), id: "l3")
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
        // Far off the track, where nothing covers it.
        race.cars[0].state.position = Vec2(-2000, -2000)
        race.cars[0].state.height = 0
        var order = RenderOrder.Builder()
        TrackRenderer.addCars(
            scene: scene(race), gateChrome: chrome(for: track),
            colorAt: { _ in .red }, to: &order)
        XCTAssertTrue(
            order.debugOrder.filter { $0.hasSuffix("/window") }.isEmpty,
            "nothing covers this car, so it needs no window")
    }

    /// **A car mid-CLIMB under a ramp shows through it.** The hardest case, and the
    /// one two earlier fixes both missed.
    ///
    /// A ramp climbing from 2.0 to 2.65 is road above a car at 2.01, but it belongs
    /// to no whole storey — so scanning storeys asked "is there road at storey 3?",
    /// found none within reach, and left the car hidden. Reported as "still hidden on
    /// the ramp under this other ramp", at h=2.11 and h=0.40.
    ///
    /// Sweeps EVERY centerline point at its own fractional height, which is what the
    /// storey-sampling tests could not see.
    func testACarAtAnyFractionalHeightShowsThroughRoadAboveIt() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.towerOfBabel), id: "babel")
        var checked = 0
        for index in track.centerline.indices {
            let point = track.centerline[index]
            let height = track.heights[index]
            // Is any road genuinely a level or more above this point, and over it?
            let covered = track.centerline.indices.contains { other in
                let roadHeight = track.height(ofSegment: other)
                guard roadHeight > height + Track.levelSeparation else { return false }
                let a = track.centerline[other]
                let b = track.centerline[(other + 1) % track.centerline.count]
                return point.distance(toSegment: a, b)
                    < track.footprintHalfWidth(atHeight: roadHeight)
            }
            guard covered else { continue }
            var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
            race.cars[0].state.position = point
            race.cars[0].state.height = height
            var order = RenderOrder.Builder()
            TrackRenderer.addCars(
                scene: scene(race), gateChrome: chrome(for: track),
                colorAt: { _ in .red }, to: &order)
            XCTAssertFalse(
                order.debugOrder.filter { $0.hasSuffix("/window") }.isEmpty,
                "a car at h=\(height) at \(point) has road above it and must show through")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 50, "the sweep must cover a real stretch of track")
        // And the fixture must actually exercise fractional heights, or this test
        // is just the storey sweep again.
        let fractional = track.heights.filter { abs($0 - $0.rounded()) > 0.1 }
        XCTAssertGreaterThan(
            fractional.count, 20, "the fixture must have ramps, not only flat decks")
    }

    /// **A storey's clip includes its RAMPS, not only its flat runs.**
    ///
    /// The window is clipped to the covering road so a hole never spills onto the
    /// grass. That clip matched segments at an exact whole height, so a ramp climbing
    /// through a level — which has no segment at any whole height — was absent from
    /// its own storey's clip: the window had nothing to draw in and stayed invisible.
    func testAStoreysClipIncludesItsRamps() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.towerOfBabel), id: "babel")
        var checked = 0
        for index in track.centerline.indices {
            let height = track.height(ofSegment: index)
            // Mid-climb segments only: those are the ones an exact-height match drops.
            guard abs(height - height.rounded()) > 0.15 else { continue }
            let storey = Track.level(of: height)
            let mid =
                (track.centerline[index]
                    + track.centerline[(index + 1) % track.centerline.count]) * 0.5
            let clip = TrackRenderer.probeCoveringDeck(track: track, storey: storey)
            XCTAssertTrue(
                clip.contains(CGPoint(x: mid.x, y: mid.y)),
                "a ramp segment at h=\(height) must be inside storey \(storey)'s clip")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 20, "the fixture must have plenty of ramp")
        // NOTE: this passes even with the old exact-height keying, because the clip
        // strokes each segment ~99 units wide and a neighbouring flat run's band
        // covers a mid-climb point anyway. The keying is still the honest rule —
        // measured 98 segments in storey 2 by level against 54 by exact height — but
        // point-containment cannot tell the two apart, so treat this as a guard on
        // the clip being non-empty over ramps rather than as coverage of the keying.
    }

    /// **One window per covering storey, never two.** A car under a single deck
    /// gets one hole, not one per road segment that happens to cover it.
    ///
    /// Deliberately NOT asserting that the window avoids the car's own layer: it
    /// does not, by design. `carStorey` paints a car under a deck in THAT deck's
    /// layer — that is what makes it visible at all — and `RenderOrder` sorts
    /// `window` before `car` within a storey so the hole is cut first and the car
    /// drawn through it. An earlier version of this test asserted the opposite and
    /// failed for the right reason.
    func testOneWindowPerCoveringStorey() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.towerOfBabel), id: "babel")
        var checked = 0
        for index in track.centerline.indices where index % 7 == 0 {
            var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
            race.cars[0].state.position = track.centerline[index]
            race.cars[0].state.height = track.heights[index]
            var order = RenderOrder.Builder()
            TrackRenderer.addCars(
                scene: scene(race), gateChrome: chrome(for: track),
                colorAt: { _ in .red }, to: &order)
            let windows = order.debugOrder.filter { $0.hasSuffix("/window") }
            XCTAssertEqual(
                windows.count, Set(windows).count,
                "at \(track.centerline[index]) a storey cut more than one window: \(windows)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 10)
    }

    private func scene(_ race: Race) -> WorldScene {
        WorldScene(
            race: race, marks: MarkStore(), gateSpans: [], colors: [.red],
            mapRect: CGRect(x: 0, y: 0, width: 400, height: 400))
    }

    private func chrome(for track: Track) -> TrackRenderer.GateChrome {
        TrackRenderer.GateChrome(
            spans: track.gates.map { (a: $0.a, b: $0.b) }, nextByGate: [:],
            worldCenter: Vec2(track.size.x / 2, track.size.y / 2),
            heights: track.gates.map(\.height))
    }
}
