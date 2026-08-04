import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Three storeys above the ground.** Raised from one to see where the height
/// model creaks before committing to it — the level vocabulary was built for this
/// (`TrackLevel.swift`), so the change is one constant and everything else derives.
final class Level3Tests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    /// The storeys are contiguous and non-overlapping: every height a track can
    /// reach is drawn, in exactly one layer.
    func testEveryHeightIsDrawnExactlyOnce() {
        for step in 0...(Track.highestLevel * 20) {
            let height = Double(step) / 20
            let layers = (0...Track.highestLevel).filter {
                TrackRenderer.storeyBand($0).contains(height)
            }
            XCTAssertEqual(
                layers.count, 1,
                "height \(height) must be drawn by exactly one storey, got \(layers)")
        }
    }

    /// **`everyStorey` must cover every storey.** It defaults the renderers'
    /// `heightRange`, and it was a hardcoded `-1...2` — so raising the ceiling
    /// silently clipped the top storey out of the drawing for any caller that took
    /// the default. (The editor passes the full range explicitly, which is why
    /// nothing looked wrong.)
    func testEveryStoreyCoversTheWholeWorld() {
        for storey in Track.lowestLevel...Track.highestLevel {
            let height = Double(storey) * Track.levelHeight
            XCTAssertTrue(
                Track.everyStorey.contains(height),
                "storey \(storey) at height \(height) must be inside `everyStorey`")
        }
        XCTAssertTrue(
            Track.everyStorey.contains(Double(Track.highestLevel)),
            "the top storey especially — that is the one a hardcoded range drops")
    }

    /// The airborne pass sits above every storey there is, so a flying car is never
    /// painted under a deck. It derives from `highestLevel` rather than a literal.
    func testTheAirbornePassIsAboveEveryStorey() {
        for storey in 0...Track.highestLevel {
            XCTAssertLessThan(
                storey, Track.highestLevel + 1,
                "the airborne layer must outrank every road storey")
        }
    }

    /// **A coiled climb reaches the top storey without growing.** A straight climb
    /// costs ~1920 units of canvas per level, which is why height 3 looked
    /// impractical; turning while climbing costs nothing, so the ceiling is usable.
    func testACoiledClimbCostsNoFootprint() {
        struct Footprint {
            var width: Double
            var height: Double
            var topReached: Double
        }
        func footprint(to target: Int) -> Footprint {
            var pieces: [PieceID] = [Pieces.startGrid]
            var pitches: [Pitch] = [.flat]
            for _ in 0..<(target * 2) {
                pieces.append(Pieces.curve90TightLeft)
                pitches.append(.up)
            }
            for _ in 0..<(target * 2) {
                pieces.append(Pieces.curve90TightLeft)
                pitches.append(.down)
            }
            let walk = TrackLayout(pieces: pieces, pitches: pitches, gateSeams: [0]).walk()
            XCTAssertNil(walk.failure, "a coil to \(target) must walk")
            let pts = walk.placed.flatMap { $0.heightedSamples(degreesPerSample: 15) }
            let xs = pts.map(\.point.x), ys = pts.map(\.point.y)
            return Footprint(
                width: (xs.max() ?? 0) - (xs.min() ?? 0),
                height: (ys.max() ?? 0) - (ys.min() ?? 0),
                topReached: pts.map(\.height).max() ?? 0)
        }
        let one = footprint(to: 1)
        let top = footprint(to: Track.highestLevel)
        XCTAssertEqual(
            top.topReached, Double(Track.highestLevel), accuracy: 0.01,
            "the coil must actually reach the top")
        XCTAssertEqual(top.width, one.width, accuracy: 1, "and cost no more width")
        XCTAssertEqual(top.height, one.height, accuracy: 1, "nor height")
    }

    /// The sim works up there: a track lifted to the top storey compiles, carries
    /// walls, and the AI can lap it.
    func testTheAICanLapAtTheTopStorey() throws {
        var layout = TrackLayout(
            pieces: [
                Pieces.startGrid, Pieces.straight, Pieces.curve90MediumLeft,
                Pieces.curve90MediumLeft, Pieces.straight, Pieces.straight,
                Pieces.curve90MediumLeft, Pieces.curve90MediumLeft, Pieces.straight,
            ], gateSeams: [0, 4])
        layout.originHeight = Double(Track.highestLevel)
        layout.railed = Set(layout.pieces.indices)
        XCTAssertTrue(
            TrackValidator.validate(layout).isSaveable,
            "a ring at the top storey is a legal track")
        let track = try PieceCompiler.compile(layout, id: "top")
        XCTAssertEqual(track.heights.max() ?? 0, Double(Track.highestLevel), accuracy: 0.01)
        XCTAssertFalse(track.walls.filter { $0.kind == .rail }.isEmpty, "railed up there too")

        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
        var driver = AIDriver()
        var ticks = 0
        while race.cars[0].progress.finishedAt == nil, ticks < 90 * Race.tickRate {
            race.advance(
                inputs: [PlayerID(0): driver.input(car: race.cars[0].state, track: track)])
            ticks += 1
        }
        XCTAssertNotNil(
            race.cars[0].progress.finishedAt, "the AI must lap a track at the top storey")
        XCTAssertEqual(
            race.cars[0].state.height, Double(Track.highestLevel), accuracy: 0.01,
            "and stay up there")
    }

    /// **The rail is where the road ends, at every storey.**
    ///
    /// `halfWidth(atHeight:)` scales with height and so does the drawn ribbon, but
    /// rails used to be laid at a flat `width / 2` — so they sat inboard of the
    /// asphalt by `12 × height` units. Invisible at the deck; 36 units at height 3,
    /// where it reads as a transparent wall well inside the visible road ("the car
    /// doesn't reach the walls on level 3, but hits a transparent wall before it").
    func testRailsSitAtTheDrivableEdgeAtEveryStorey() throws {
        var layout = TrackLayout(
            pieces: [
                Pieces.startGrid, Pieces.straight, Pieces.curve90MediumLeft,
                Pieces.curve90MediumLeft, Pieces.straight, Pieces.straight,
                Pieces.curve90MediumLeft, Pieces.curve90MediumLeft, Pieces.straight,
            ], gateSeams: [0, 4])
        layout.railed = Set(layout.pieces.indices)
        for storey in 1...Track.highestLevel {
            layout.originHeight = Double(storey)
            let track = try PieceCompiler.compile(layout, id: "s\(storey)")
            let rails = track.walls.filter { $0.kind == .rail }
            XCTAssertFalse(rails.isEmpty, "storey \(storey) must be railed")
            let n = track.centerline.count
            var worst = 0.0
            for i in track.centerline.indices {
                let point = track.centerline[i]
                let height = track.heights[i]
                let dir = (track.centerline[(i + 1) % n] - point).normalized
                guard dir.length > 0 else { continue }
                for sign in [1.0, -1.0] {
                    let edge =
                        point + dir.perpendicular * sign * track.halfWidth(atHeight: height)
                    guard
                        let nearest = rails.filter({ abs($0.height - height) < 0.15 })
                            .map({ edge.distance(toSegment: $0.a, $0.b) }).min()
                    else { continue }
                    worst = max(worst, nearest)
                }
            }
            XCTAssertLessThan(
                worst, 4,
                "at storey \(storey) every rail must sit on the drivable edge, not inboard of it")
        }
    }

    /// **A gate spans its own road, at every storey.**
    ///
    /// The span used a flat `width / 2` while the road widens with height, so a
    /// raised gate was NARROWER than the asphalt it crosses. Running wide up there
    /// missed the checkpoint — a correctness bug, not just a thin-looking bar.
    ///
    /// Uses the REPORTED track, because the bug only shows where the neighbour-lane
    /// cap bites: on a wide-open ring the grass margin swamps the difference and the
    /// gate covers ~3x its road either way. On this one, a level-3 gate covered 63%
    /// of its road against 248% on the ground.
    func testAGateCoversItsRoadAtEveryStorey() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.threeStorey), id: "l3")
        var checked = 0
        for gate in track.gates {
            let span = (gate.b - gate.a).length
            let road = track.halfWidth(atHeight: gate.height) * 2
            XCTAssertGreaterThan(
                span, road - 1,
                "a gate at height \(gate.height) must span its whole road")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "the fixture must carry gates")
        XCTAssertGreaterThan(
            track.heights.max() ?? 0, 2.5, "and must actually reach the top storey")
    }

    /// **Height reads as brightness at every storey.** The shade used to divide by
    /// one `levelHeight` and clamp, so it topped out at the first deck — with three
    /// storeys, heights 1, 2 and 3 were all the same gray.
    func testEveryStoreyHasItsOwnShade() {
        var seen: [Double] = []
        for storey in Track.lowestLevel...Track.highestLevel {
            let shade = EditorRenderer.roadShadeWhite(at: Double(storey) * Track.levelHeight)
            for previous in seen {
                XCTAssertGreaterThan(
                    abs(shade - previous), 0.05,
                    "storey \(storey) must be visibly distinct from every other")
            }
            seen.append(shade)
        }
        XCTAssertEqual(seen.count, Track.highestLevel - Track.lowestLevel + 1)
    }

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

    /// **A car never gets a window in its OWN storey**, and never one per storey
    /// where only one road covers it. The scan must start strictly above the car:
    /// including its own level cuts a hole in the road it is driving on.
    func testAWindowIsNeverCutInTheCarsOwnRoad() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.threeStorey), id: "l3")
        for storey in 0...Track.highestLevel {
            guard
                let index = track.centerline.indices.first(where: {
                    Track.level(of: track.heights[$0]) == storey
                })
            else { continue }
            var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: nil))
            race.cars[0].state.position = track.centerline[index]
            race.cars[0].state.height = track.heights[index]
            var order = RenderOrder.Builder()
            TrackRenderer.addCars(
                scene: scene(race), gateChrome: chrome(for: track),
                colorAt: { _ in .red }, to: &order)
            let windows = order.debugOrder.filter { $0.hasSuffix("/window") }
            XCTAssertFalse(
                windows.contains("\(storey)/window"),
                "a car ON storey \(storey) must not have a hole cut in its own road")
            // And each covering storey contributes at most one window.
            XCTAssertEqual(
                windows.count, Set(windows).count,
                "one window per covering storey at most, got \(windows)")
        }
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

    /// **An off-road car is binned by what is BENEATH it    /// **An off-road car is binned by what is BENEATH it, not by rounding its own
    /// height.** Rounding flipped the storey at every half level, so a car on the
    /// grass beside a ramp switched from painting under the wall to over it partway
    /// up — and a third storey adds the same flip at 1.5 and 2.5.
    func testAnOffRoadCarFollowsTheRoadBeneathIt() throws {
        let track = try PieceCompiler.compile(
            TrackCode.decode(TestTracks.Code.bridgeRing), id: "t")
        // A point well off the road, beside the ring.
        let outside = Vec2(-400, -400)
        for height in [0.4, 0.5, 0.6, 1.4, 1.5, 1.6, 2.4, 2.5, 2.6] {
            var car = CarState(position: outside)
            car.height = height
            let storey = TrackRenderer.carStorey(of: car, on: track)
            XCTAssertEqual(
                storey,
                TrackRenderer.storey(ofTop: track.deckTop(at: outside, preferHeight: height)),
                "an off-road car at \(height) must follow the road beneath it")
        }
    }
}
