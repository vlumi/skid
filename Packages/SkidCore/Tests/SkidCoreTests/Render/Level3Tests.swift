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

    /// **An off-road car is binned by what is BENEATH it, not by rounding its own
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
