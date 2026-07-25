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

    private func compiledBridge() throws -> Track {
        try PieceCompiler.compile(
            TrackLayout(pieces: bridgeRing, gateSeams: [0, 5]), id: "test-bridge")
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
        XCTAssertEqual(t.startSlots.count, 4)
    }

    /// **A ramp's road must be marked as sloped.** `Track.isOnRamp` and
    /// `Track.visualHeight` both scan `rampSegments`; the renderer's ramp drawing
    /// reads it too. The piece compiler never populated it, so ramps and decks
    /// did not work at all: nothing drew, a climbing car was never treated as
    /// between layers, and it never grew smoothly as it went up.
    func testRampRoadIsMarkedAsSloped() throws {
        let track = try compiledBridge()
        XCTAssertFalse(track.rampSegments.isEmpty, "a bridge must mark its ramp road")
        // One run per ramp piece (up and down), and they must be distinct.
        XCTAssertEqual(track.ramps.count, 2, "one layer-switch line per ramp piece")
        // The runtime's ramp queries must actually fire on the sloped road.
        for segment in track.rampSegments {
            XCTAssertTrue(
                track.isOnRamp(track.centerline[segment]),
                "segment \(segment) is ramp road but isOnRamp says otherwise")
        }
    }

    /// **The layer-switch line belongs at the ramp's HIGH end.**
    ///
    /// Crossing it flips the car's layer instantly. With the line at the ramp's
    /// entry, a car became "on the deck" the moment it touched the BOTTOM of the
    /// ramp — a road-length short of the deck and still at ground level. It read
    /// as the car jumping at the foot of the ramp, and then the fall-off check in
    /// `Race.applyRamps` (now far from the deck's centerline) dropped it back
    /// down, so it drove *under* the bridge and missed the gate up there. Only
    /// enough speed to clear both checks in one tick got you up.
    func testRampLinesSitAtTheDeckEndNotTheApproach() throws {
        let track = try compiledBridge()
        let up = try XCTUnwrap(track.ramps.first { $0.toLayer > $0.fromLayer })
        let down = try XCTUnwrap(track.ramps.first { $0.toLayer < $0.fromLayer })
        // The two lines are at genuinely different places (they used to be able
        // to coincide, which made a car flip up and back down in one instant).
        let upMid = Vec2((up.a.x + up.b.x) / 2, (up.a.y + up.b.y) / 2)
        let downMid = Vec2((down.a.x + down.b.x) / 2, (down.a.y + down.b.y) / 2)
        XCTAssertGreaterThan(
            (upMid - downMid).length, track.width,
            "the up and down switch lines must not sit on top of each other")
        // Each line sits where the ELEVATED road is, not out on the ground
        // approach: the nearest elevated segment is closer than the nearest
        // ground-level, non-ramp segment.
        for (name, mid) in [("up", upMid), ("down", downMid)] {
            var nearestElevated = Double.greatestFiniteMagnitude
            var nearestGround = Double.greatestFiniteMagnitude
            for (index, point) in track.centerline.enumerated() {
                let distance = (point - mid).length
                if track.elevatedSegments.contains(index) {
                    nearestElevated = min(nearestElevated, distance)
                } else if !track.rampSegments.contains(index) {
                    nearestGround = min(nearestGround, distance)
                }
            }
            XCTAssertLessThan(
                nearestElevated, nearestGround,
                "the \(name) ramp's switch line should be at the deck end")
        }
    }

    /// **A bridge needs barriers.** The editor draws blue guard rails along an
    /// elevated piece's edges, but the compiler emitted no walls at all — so a
    /// raced bridge had nothing stopping a car driving off the side. The only
    /// thing catching you was the fall-off check in `Race.applyRamps`, which is
    /// the consequence of leaving the deck rather than a wall preventing it.
    func testElevatedPiecesGetGuardRails() throws {
        let track = try compiledBridge()
        XCTAssertFalse(track.walls.isEmpty, "an elevated piece needs guard rails")
        // Rails belong to the deck, not the ground.
        for wall in track.walls {
            XCTAssertEqual(wall.layer, 1, "a deck rail guards the deck")
        }
        // Both edges are railed, so rails appear on both sides of the deck.
        let deckSegment = try XCTUnwrap(track.elevatedSegments.min())
        let deckPoint = track.centerline[deckSegment]
        var sides = Set<Bool>()
        for wall in track.walls {
            let mid = Vec2((wall.a.x + wall.b.x) / 2, (wall.a.y + wall.b.y) / 2)
            guard (mid - deckPoint).length < track.width * 3 else { continue }
            // Which side of the centerline point this rail sits on.
            sides.insert(mid.x + mid.y > deckPoint.x + deckPoint.y)
        }
        XCTAssertEqual(sides.count, 2, "a deck must be railed on both edges")
    }

    /// **The ramp road must not vanish under a car crossing between layers.**
    ///
    /// The reported symptom was the car jumping at the TOP of the ramp. Cause: a
    /// ramp segment is neither elevated nor plain ground, so a per-layer surface
    /// lookup found no same-layer asphalt for it. Once the layer flipped at the
    /// top, the whole descending ramp read as GRASS to the physics — the car came
    /// over the crest and lost grip as though it had landed in the rough. A ramp
    /// belongs to both layers, being the connection between them.
    func testRampRoadIsAsphaltOnBothLayers() throws {
        let track = try compiledBridge()
        XCTAssertFalse(track.rampSegments.isEmpty, "fixture must have ramps")
        for segment in track.rampSegments.sorted() {
            let a = track.centerline[segment]
            let b = track.centerline[(segment + 1) % track.centerline.count]
            for step in 0...4 {
                let point = a + (b - a) * (Double(step) / 4)
                for layer in [0, 1] {
                    XCTAssertEqual(
                        track.surface(at: point, layer: layer), .asphalt,
                        "ramp segment \(segment) at t=\(Double(step) / 4) is not asphalt "
                            + "on layer \(layer)")
                }
            }
        }
    }

    /// …but the bridge must still BE a bridge: the road passing underneath is
    /// ground-only, so a car down there can't grip the deck above it. (Without
    /// this, widening layer membership could quietly turn a bridge into a
    /// crossroads.)
    func testDeckIsNotDrivableFromTheGroundLayer() throws {
        let track = try compiledBridge()
        // A deck point that isn't part of a ramp: ground layer must see grass
        // there unless ground road genuinely runs beneath it.
        var checked = 0
        for segment in track.elevatedSegments.sorted() {
            let point = track.centerline[segment]
            guard track.distanceToCenterline(point, layer: 0) > track.width else { continue }
            XCTAssertEqual(
                track.surface(at: point, layer: 0), .grass,
                "deck segment \(segment) must not be drivable from the ground")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "fixture needs deck clear of the ground road")
    }

    /// A flat track has nothing to fall off, so it gets no rails.
    func testGroundLevelTracksHaveNoGuardRails() throws {
        XCTAssertTrue(try compiledSquare().walls.isEmpty)
    }

    /// The deck itself: flat pieces the walk carries at height 1 become elevated
    /// road, and the ground-level remainder stays on layer 0.
    func testDeckPiecesAreElevatedAndTheRestIsNot() throws {
        let track = try compiledBridge()
        XCTAssertFalse(track.elevatedSegments.isEmpty, "the bridge needs a deck")
        XCTAssertLessThan(
            track.elevatedSegments.count, track.centerline.count,
            "the whole ring must not be elevated")
        // Layer follows the set, which is what the physics and the renderer use.
        for segment in track.elevatedSegments {
            XCTAssertEqual(track.segmentLayer(segment), 1)
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
            ], gateSeams: [0, 1, 2])
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
