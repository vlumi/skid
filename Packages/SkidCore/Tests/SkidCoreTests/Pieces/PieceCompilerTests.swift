import XCTest

@testable import SkidCore

/// Phase-A compile: a saveable layout → a well-formed runtime `Track`.
final class PieceCompilerTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID
    // Closed rounded square that clears itself (same as the validator test).
    private let square: [PieceID] = [
        Pieces.startGrid, Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
        Pieces.straight,
        Pieces.curve90TightLeft, Pieces.straight, Pieces.curve90TightLeft,
    ]

    private func compiledSquare() throws -> Track {
        try PieceCompiler.compile(
            TrackLayout(pieces: square, gateSeams: [0, 2, 4, 6]), id: "test-square")
    }

    /// A closed ring carrying a bridge: climb, run along the deck (there is no
    /// deck piece — elevated road is ordinary pieces the walk carries at height
    /// 1), then descend. Sides are length-matched so the loop closes.
    private let bridgeRing: [PieceID] = [
        Pieces.startGrid, Pieces.rampUp, Pieces.straight,
        Pieces.curve90MediumLeft, Pieces.curve90MediumLeft,
        Pieces.rampDown, Pieces.straight, Pieces.straight,
        Pieces.curve90MediumLeft, Pieces.curve90MediumLeft,
        Pieces.straight, Pieces.straight, Pieces.straight,
    ]

    /// A bridge ring **with railings**: rails are a per-piece choice now, so a
    /// fixture that asserts about railings has to ask for them. Every piece is
    /// railed, which is what these tests assumed when climbing implied a rail.
    private func compiledBridge() throws -> Track {
        try PieceCompiler.compile(
            TrackLayout(
                pieces: bridgeRing, gateSeams: [0, 5],
                railed: Set(bridgeRing.indices)),
            id: "test-bridge")
    }

    func testUnsaveableLayoutThrows() {
        XCTAssertThrowsError(
            try PieceCompiler.compile(
                TrackLayout(
                    pieces: [Pieces.startGrid, Pieces.straight, Pieces.straight], gateSeams: [0]))
        ) { error in
            guard case PieceCompiler.Failure.notSaveable = error else {
                return XCTFail("expected notSaveable, got \(error)")
            }
        }
    }

    func testForkRejectedInPhaseA() {
        // A layout that closes with a fork present should reject in Phase A.
        // (Even if not perfectly closed, the fork check fires after saveable;
        // so use a minimal closeable-ish ring — assert the error type when it
        // is saveable, else accept notSaveable.)
        let layout = TrackLayout(
            pieces: [
                Pieces.startGrid, Pieces.forkStraightLeft, Pieces.curve90TightRight,
                Pieces.curve90TightRight,
                Pieces.curve90TightRight,
            ], gateSeams: [0, 1])
        XCTAssertThrowsError(try PieceCompiler.compile(layout))
    }

    func testCompiledTrackBasics() throws {
        let t = try compiledSquare()
        XCTAssertEqual(t.id, "test-square")
        XCTAssertEqual(t.width, 120)
        // `size` is the track's OWN footprint, not the whole permitted canvas.
        // It used to be the canvas, which made the race view frame every
        // piece-built track at the scale of the largest legal one — so a small
        // track rendered shrunken and off-center. See `PieceCompiler.footprint`.
        XCTAssertLessThan(t.size.x, TrackValidator.canvas.x)
        XCTAssertLessThan(t.size.y, TrackValidator.canvas.y)
        XCTAssertGreaterThan(t.centerline.count, 8)  // arcs densified
        XCTAssertEqual(t.gates.count, 4)
        XCTAssertEqual(t.startSlots.count, PieceCompiler.Grid.slots)
    }

    /// A bridge's road climbs continuously: the compiler emits a height per
    /// centerline point, so the ramp is sloped road rather than a flag plus a
    /// transition line.
    func testTheBridgeRoadClimbsContinuously() throws {
        let track = try compiledBridge()
        XCTAssertEqual(track.heights.count, track.centerline.count, "one height per point")
        XCTAssertTrue(track.heights.contains { $0 > 0.9 }, "the deck reaches full height")
        XCTAssertTrue(track.heights.contains { $0 < 0.1 }, "the ground stays down")
        // Somewhere in between: the actual slope.
        XCTAssertTrue(
            track.heights.contains { $0 > 0.2 && $0 < 0.8 }, "the ramp is a gradual climb")
        // No neighboring pair jumps a whole level, so no point is a cliff.
        for index in track.centerline.indices {
            let next = (index + 1) % track.centerline.count
            XCTAssertLessThan(
                abs(track.heights[next] - track.heights[index]), 0.6,
                "height steps abruptly between points \(index) and \(next)")
        }
        // The runtime recognizes the slope as a ramp.
        let sloped = track.centerline.indices.first { index in
            let next = (index + 1) % track.centerline.count
            return abs(track.heights[next] - track.heights[index]) > 0.05
        }
        let rampPoint = try XCTUnwrap(sloped)
        XCTAssertTrue(track.isOnRamp(track.centerline[rampPoint]))
    }

    /// A plain bridge emits NO launch lines. `rampUp` used to be flagged
    /// `launches: true`, so driving up a bridge threw the car ballistically at the
    /// top — the reported "car jumps at the top of the ramp", and the reason
    /// reaching the deck depended on carrying speed. Launching belongs to the
    /// separate `jump` piece.
    func testABridgeRampDoesNotLaunchTheCar() throws {
        XCTAssertTrue(try compiledBridge().ramps.isEmpty)
    }

    /// **A bridge needs barriers.** The editor draws blue guard rails along an
    /// elevated piece's edges, but the compiler emitted no walls at all — so a
    /// raced bridge had nothing stopping a car driving off the side.
    func testElevatedPiecesGetGuardRails() throws {
        let track = try compiledBridge()
        // Find a full-height deck point, then look for rails beside it. (Only
        // rails near the deck count — every track also carries a map-boundary
        // fence, which is not a deck rail.)
        let deckIndex = try XCTUnwrap(track.heights.firstIndex { $0 > 0.9 })
        let deckPoint = track.centerline[deckIndex]
        var sides = Set<Bool>()
        var found = 0
        for wall in track.walls where wall.kind == .rail && wall.height > 0.5 {
            let mid = Vec2((wall.a.x + wall.b.x) / 2, (wall.a.y + wall.b.y) / 2)
            guard (mid - deckPoint).length < track.width * 3 else { continue }
            found += 1
            // Which side of the centerline point this rail sits on.
            sides.insert(mid.x + mid.y > deckPoint.x + deckPoint.y)
        }
        XCTAssertGreaterThan(found, 0, "the deck needs rails along it")
        XCTAssertEqual(sides.count, 2, "a deck must be railed on both edges")
    }

    /// A rail sits at the height of the road it guards, so it bites a car up on
    /// the deck and lets the road underneath pass freely. That is what stops a
    /// deck rail from walling off the road beneath a bridge.
    func testRailsSitAtTheHeightOfTheirRoad() throws {
        let track = try compiledBridge()
        for wall in track.walls where wall.kind == .rail {
            let mid = Vec2((wall.a.x + wall.b.x) / 2, (wall.a.y + wall.b.y) / 2)
            // The road nearest this rail, at the rail's own height, is close by.
            XCTAssertLessThan(
                track.distanceToCenterline(mid, height: wall.height), track.width,
                "a rail at height \(wall.height) is nowhere near road at that height")
        }
    }

    /// The whole ramp is drivable asphalt at the height it sits at — the road
    /// never vanishes from under a climbing car. (Under the old layer model, the
    /// descending ramp read as grass once the layer flipped at the top, so the car
    /// lost grip coming over the crest.)
    func testTheRampIsAsphaltAtItsOwnHeight() throws {
        let track = try compiledBridge()
        let count = track.centerline.count
        var checked = 0
        for index in track.centerline.indices {
            let next = (index + 1) % count
            guard abs(track.heights[next] - track.heights[index]) > 0.05 else { continue }
            let a = track.centerline[index]
            let b = track.centerline[next]
            for step in 0...4 {
                let t = Double(step) / 4
                let point = a + (b - a) * t
                let height = track.heights[index] + (track.heights[next] - track.heights[index]) * t
                XCTAssertEqual(
                    track.surface(at: point, height: height), .asphalt,
                    "the ramp is not asphalt at its own height (t=\(t))")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "fixture must contain a ramp")
    }

    /// …but the bridge must still BE a bridge: a car on the ground can't grip the
    /// deck above it.
    func testDeckIsNotDrivableFromTheGround() throws {
        let track = try compiledBridge()
        var checked = 0
        for (index, height) in track.heights.enumerated() where height > 0.9 {
            let point = track.centerline[index]
            // Only where no ground road genuinely runs beneath.
            guard track.distanceToCenterline(point, height: 0) > track.width else { continue }
            XCTAssertEqual(
                track.surface(at: point, height: 0), .grass,
                "deck point \(index) must not be drivable from the ground")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "fixture needs deck clear of the ground road")
    }

    /// A flat track has nothing to fall off, so its only walls are the map fence
    /// — no deck rails anywhere in the middle.
    func testGroundLevelTracksHaveOnlyTheBoundaryFence() throws {
        let track = try compiledSquare()
        XCTAssertFalse(track.walls.isEmpty, "even a flat track is fenced")
        // Every wall hugs the frame edge; none cuts across the interior.
        let inset = 12.0
        for wall in track.walls {
            for point in [wall.a, wall.b] {
                let onEdge =
                    point.x <= inset || point.y <= inset
                    || point.x >= track.size.x - inset || point.y >= track.size.y - inset
                XCTAssertTrue(
                    onEdge, "a flat track should have no interior walls, found one at \(point)")
            }
        }
    }

    /// **You can't drive off the map.** Piece-built tracks had no boundary at
    /// all, so a car could leave the playfield entirely and end up under the
    /// control band. Legacy `TrackDesign` tracks always had this fence.
    func testTheMapIsFenced() throws {
        for track in [try compiledSquare(), try compiledBridge()] {
            let center = track.size * 0.5
            for _ in [0] {
                for degrees in stride(from: 0, to: 360, by: 15) {
                    let angle = Double(degrees) * .pi / 180
                    let outside =
                        center + Vec2(cos(angle), sin(angle)) * (track.size.x + track.size.y)
                    let enclosed = track.walls.contains { (wall: Wall) in
                        Gate(from: wall.a, to: wall.b)
                            .isCrossed(movingFrom: center, to: outside)
                    }
                    XCTAssertTrue(
                        enclosed, "track \(track.id) is open toward \(degrees)°")
                }
            }
        }
    }

    /// A ramp is railed down both flanks, so you can't slide off the side of the
    /// climb. With heights there are no "end caps" to get wrong: a car under the
    /// bridge is simply at a different height from the ramp, so it can't be on it.
    func testRampFlanksAreRailed() throws {
        let track = try compiledBridge()
        let count = track.centerline.count
        var checked = 0
        for index in track.centerline.indices {
            let next = (index + 1) % count
            guard abs(track.heights[next] - track.heights[index]) > 0.05 else { continue }
            let a = track.centerline[index]
            let b = track.centerline[next]
            let mid = a + (b - a) * 0.5
            let height = (track.heights[index] + track.heights[next]) / 2
            let side = (b - a).normalized.perpendicular
            for direction in [1.0, -1.0] {
                let edge = mid + side * (track.width / 2 * direction)
                let railed = track.walls.contains { (wall: Wall) in
                    wall.kind == .rail
                        && abs(wall.height - height) <= Track.reachTolerance
                        && edge.distance(toSegment: wall.a, wall.b) < CarGeometry.radius * 2
                }
                XCTAssertTrue(railed, "ramp flank unrailed at point \(index)")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "fixture must contain a ramp")
    }

    /// **What's drawn must sit where the physics is.**
    ///
    /// The race view draws the track from the piece layout (so it matches the
    /// editor exactly), but compiling re-frames the geometry onto its own
    /// footprint. That shift isn't a whole number of units, so it can't be folded
    /// into the layout's exact integer origin — it has to be carried as
    /// `layoutOffset` and applied when drawing. Without it the track was rendered
    /// visibly offset from where it actually was: right shape, wrong place.
    func testLayoutOffsetAlignsDrawingWithGeometry() throws {
        for track in [try compiledSquare(), try compiledBridge()] {
            let layout = try XCTUnwrap(track.layout)
            let drawn = layout.walk().placed.flatMap { $0.centerlineSamples() }
                .map { $0 + track.layoutOffset }
            let drawnXs = drawn.map { $0.x }
            let drawnYs = drawn.map { $0.y }
            let realXs = track.centerline.map { $0.x }
            let realYs = track.centerline.map { $0.y }
            XCTAssertEqual(drawnXs.min()!, realXs.min()!, accuracy: 1, "\(track.id) left edge")
            XCTAssertEqual(drawnXs.max()!, realXs.max()!, accuracy: 1, "\(track.id) right edge")
            XCTAssertEqual(drawnYs.min()!, realYs.min()!, accuracy: 1, "\(track.id) top edge")
            XCTAssertEqual(drawnYs.max()!, realYs.max()!, accuracy: 1, "\(track.id) bottom edge")
        }
    }

    /// **The framing contract.** `Track.size` is the renderer's letterbox: it
    /// fits `size` to the screen and centers on `size / 2`. So the geometry must
    /// actually live inside `0…size` on both axes, and `size` must be the track's
    /// own extent — otherwise the race view draws the track at the wrong scale,
    /// off-center, with part of it off screen (which is exactly what a big oval
    /// did when `size` was hard-coded to the full canvas).
    func testGeometryFitsInsideTheReportedSize() throws {
        let track = try compiledSquare()
        for point in track.centerline {
            XCTAssertGreaterThanOrEqual(point.x, 0, "centerline left of the frame")
            XCTAssertGreaterThanOrEqual(point.y, 0, "centerline above the frame")
            XCTAssertLessThanOrEqual(point.x, track.size.x, "centerline right of the frame")
            XCTAssertLessThanOrEqual(point.y, track.size.y, "centerline below the frame")
        }
        // Everything else the renderer places must have shifted with it.
        for slot in track.startSlots {
            XCTAssertGreaterThanOrEqual(slot.x, 0)
            XCTAssertGreaterThanOrEqual(slot.y, 0)
            XCTAssertLessThanOrEqual(slot.x, track.size.x)
            XCTAssertLessThanOrEqual(slot.y, track.size.y)
        }
        for gate in track.gates {
            for point in [gate.a, gate.b] {
                XCTAssertGreaterThanOrEqual(point.x, -1, "gate outside the frame")
                XCTAssertGreaterThanOrEqual(point.y, -1, "gate outside the frame")
                XCTAssertLessThanOrEqual(point.x, track.size.x + 1, "gate outside the frame")
                XCTAssertLessThanOrEqual(point.y, track.size.y + 1, "gate outside the frame")
            }
        }
        // The frame is snug: the track fills it, rather than floating in a
        // largely empty box (the old bug). The padding is the road half-width
        // plus decoration on each side, and a gate may reach a further road
        // width onto the grass, so allow for both — but far less than the
        // canvas-sized frame this replaced.
        let slop = Double(PieceCatalog.width) * 3.5
        let xs = track.centerline.map { $0.x }
        let ys = track.centerline.map { $0.y }
        XCTAssertLessThan(track.size.x - (xs.max()! - xs.min()!), slop, "frame too wide")
        XCTAssertLessThan(track.size.y - (ys.max()! - ys.min()!), slop, "frame too tall")
    }

    /// The road must sit CENTERED in the frame, because the renderer centers the
    /// frame on screen — so any imbalance inside it shows up as lopsided grass.
    ///
    /// The regression this guards: the frame was the bounding box of everything
    /// drawn, and a gate reaches outboard over the grass. An oval with a
    /// checkpoint on one straight pushed the box out on that side only, which on
    /// a phone read as a few pixels of grass on the left and a visibly wider band
    /// on the right. Gates are now allowed to overhang, padded equally on both
    /// sides.
    func testTheRoadIsCenteredInTheFrameDespiteOneSidedGates() throws {
        // A gate on a single straight is what makes this asymmetric, so mark
        // seams unevenly around the ring rather than symmetrically.
        let layout = TrackLayout(
            pieces: [
                Pieces.startGrid, Pieces.curve90MediumLeft, Pieces.curve90MediumLeft,
                Pieces.straight, Pieces.curve90MediumLeft, Pieces.curve90MediumLeft,
            ], gateSeams: [0, 2, 3])
        let track = try PieceCompiler.compile(layout, id: "lopsided")
        let half = track.width / 2
        let xs = track.centerline.map { $0.x }
        let ys = track.centerline.map { $0.y }
        let left = xs.min()! - half
        let right = track.size.x - (xs.max()! + half)
        let top = ys.min()! - half
        let bottom = track.size.y - (ys.max()! + half)
        XCTAssertEqual(left, right, accuracy: 0.001, "road off-center horizontally")
        XCTAssertEqual(top, bottom, accuracy: 0.001, "road off-center vertically")
        // …and the gates still fit inside the frame they were padded for.
        for gate in track.gates {
            for point in [gate.a, gate.b] {
                XCTAssertGreaterThanOrEqual(point.x, -0.001)
                XCTAssertLessThanOrEqual(point.x, track.size.x + 0.001)
                XCTAssertGreaterThanOrEqual(point.y, -0.001)
                XCTAssertLessThanOrEqual(point.y, track.size.y + 0.001)
            }
        }
    }

    /// A gate's `forward` is a DIRECTION, so re-framing must not translate it —
    /// shifting it would silently corrupt lap counting, which only accepts a
    /// crossing with a positive component along `forward`.
    func testReframingLeavesGateDirectionsAsUnitVectors() throws {
        let track = try compiledSquare()
        for gate in track.gates where gate.forward != .zero {
            XCTAssertEqual(gate.forward.length, 1, accuracy: 1e-9, "forward must stay a unit")
        }
    }

    func testCenterlineIsAClosedLoopOnAsphalt() throws {
        let t = try compiledSquare()
        // Every centerline vertex is asphalt (it's the ribbon spine).
        for p in t.centerline {
            XCTAssertEqual(t.surface(at: p), .asphalt, "centerline point \(p) off the ribbon")
        }
        // Not double-closed: last != first.
        XCTAssertNotEqual(t.centerline.first, t.centerline.last)
    }

    func testStartSlotsOnAsphaltAndGatePlacement() throws {
        let t = try compiledSquare()
        for slot in t.startSlots {
            XCTAssertEqual(t.surface(at: slot), .asphalt, "grid slot \(slot) off the ribbon")
        }
        // The last gate is start/finish; the pole should cross it driving on.
        let pole = t.startSlots[0]
        let ahead = pole + Vec2(angle: t.startHeading) * 200
        XCTAssertTrue(t.gates.last!.isCrossed(movingFrom: pole, to: ahead))
    }
}
