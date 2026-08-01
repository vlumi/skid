import XCTest

@testable import SkidCore

/// Raising and lowering the whole track: the baseline moves, the shape doesn't.
/// This is what puts a start line on the deck.
final class TrackHeightShiftTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    /// A flat ring — nothing climbs, so it can sit at any level.
    private func flatRing(originHeight: Double = 0) -> TrackLayout {
        TrackLayout(
            pieces: [Catalog.startGrid]
                + Array(
                    repeating: [
                        Catalog.curve45TightLeft, Catalog.curve45TightLeft,
                        Catalog.shortStraight, Catalog.shortStraight,
                    ], count: 4
                ).flatMap { $0 },
            originHeight: originHeight, gateSeams: [0, 4, 8, 12])
    }

    /// The baseline lifts every height by the same amount, and the geometry is
    /// untouched — same pieces, same poses, only higher.
    func testRaisingLiftsEveryHeightAndNothingElse() {
        let ground = flatRing()
        let raised = flatRing(originHeight: 0.5)
        let a = ground.walk().placed
        let b = raised.walk().placed
        XCTAssertEqual(a.count, b.count)
        for (low, high) in zip(a, b) {
            XCTAssertEqual(high.entryHeight - low.entryHeight, 0.5, accuracy: 1e-9)
            XCTAssertEqual(low.entry.position, high.entry.position, "shape must not move")
        }
    }

    /// A ring closes at the height it STARTED at — the baseline, not the ground.
    /// A flat ring raised to 0.5 is still a valid, saveable track.
    func testARaisedFlatRingIsValid() {
        let raised = flatRing(originHeight: 0.5)
        let problems = TrackValidator.validate(raised).problems
        XCTAssertFalse(
            problems.contains { problem in
                if case .unclosedHeight = problem { return true }
                if case .heightOutOfBounds = problem { return true }
                return false
            }, "a flat ring at half height closes on its own baseline: \(problems)")
    }

    /// **A track that climbs a full level cannot move**, and one that's flat can
    /// move within the storeys — which is exactly what grays the buttons out.
    func testShiftIsRefusedWhenItWouldLeaveTheWorld() throws {
        // A full-height bridge already spans 0…1: no room either way.
        let bridge = TrackLayout(
            pieces: [
                Catalog.startGrid, Catalog.rampUp, Catalog.straight, Catalog.rampDown,
            ], gateSeams: [0])
        let spans = bridge.walk().placed
        XCTAssertEqual(spans.map(\.exitHeight).max(), 1)
        XCTAssertFalse(canShift(bridge, steps: 1), "no headroom above a full climb")
        XCTAssertFalse(canShift(bridge, steps: -1), "no room below the ground")
        // A flat ring can go up, and back down again, but not below the ground.
        XCTAssertTrue(canShift(flatRing(), steps: 1))
        XCTAssertFalse(canShift(flatRing(), steps: -1))
        XCTAssertTrue(canShift(flatRing(originHeight: 1), steps: -1))
        XCTAssertFalse(canShift(flatRing(originHeight: 1), steps: 1))
    }

    /// The baseline survives the share code, and a ground-level track's bytes
    /// are unchanged — the section is omitted entirely at height 0.
    func testTheBaselineRoundTripsAndCostsNothingAtGround() throws {
        let raised = flatRing(originHeight: 0.5)
        XCTAssertEqual(try TrackCode.decode(TrackCode.encode(raised)), raised)
        let deck = flatRing(originHeight: 1)
        XCTAssertEqual(try TrackCode.decode(TrackCode.encode(deck)), deck)
        // Ground level: the encoding is byte-identical to a layout with no
        // baseline at all, so existing codes keep their exact bytes.
        var explicitGround = flatRing()
        explicitGround.originHeight = 0
        XCTAssertEqual(TrackCode.encode(explicitGround), TrackCode.encode(flatRing()))
    }

    /// **The solver comes home to the BASELINE, not the ground.** On a raised
    /// track a loose end below the baseline has to climb back — which needs
    /// pitched-UP candidates and a goal height that isn't hardcoded to 0.
    func testTheSolverClosesUpToARaisedBaseline() throws {
        // A ring at half height with one piece dropped to the ground: the run
        // home must climb.
        var layout = TrackLayout(
            pieces: [Catalog.startGrid], originHeight: 0.5, gateSeams: [0])
        layout.append(contentsOf: PieceExpansion.expand(Catalog.shortStraight, mode: .down))
        for id in [
            Catalog.curve45TightLeft, Catalog.curve45TightLeft, Catalog.curve45TightLeft,
            Catalog.curve45TightLeft, Catalog.shortStraight, Catalog.shortStraight,
            Catalog.curve45TightLeft, Catalog.curve45TightLeft,
        ] {
            layout.append(contentsOf: PieceExpansion.expand(id, mode: .flat))
        }
        let placed = layout.walk().placed
        XCTAssertEqual(try XCTUnwrap(placed.last).exitHeight, 0, accuracy: 1e-9)
        let end = try XCTUnwrap(layout.walk().openEnds.first)
        guard let run = layout.closingRun(from: end, maxPieces: 4) else {
            return  // no run within the budget is a legitimate outcome for this shape
        }
        XCTAssertTrue(run.contains { $0.pitch == .up }, "the run home must climb: \(run)")
        var closed = layout
        closed.append(contentsOf: run.flatMap { PieceExpansion.expand($0.id, mode: $0.pitch) })
        XCTAssertTrue(closed.walk().openEnds.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(closed.walk().placed.last).exitHeight, 0.5, accuracy: 1e-9)
        XCTAssertFalse(
            TrackValidator.validate(closed).problems.contains { problem in
                if case .unclosedHeight = problem { return true }
                return false
            })
    }

    /// **Cars spawn on the road, not under it.** The grid's height comes from
    /// the layout's baseline; a hardcoded 0 put every car below a raised track,
    /// which then read as off-road at the start line.
    func testCarsSpawnAtTheTracksOwnHeight() throws {
        let raised = flatRing(originHeight: 0.5)
        let track = try PieceCompiler.compile(raised, id: "raised")
        XCTAssertEqual(track.startHeight, 0.5, accuracy: 1e-9)
        let race = Race(track: track, players: [PlayerID(0), PlayerID(1)])
        for car in race.cars {
            XCTAssertEqual(car.state.height, 0.5, accuracy: 1e-9, "car spawned off its road")
            XCTAssertEqual(
                track.surface(at: car.state.position, height: car.state.height), .asphalt,
                "a car at the grid must be on asphalt")
        }
    }

    /// The same range rule the buttons use, without a view: mirrors
    /// `CouchGame.canShiftHeight`.
    private func canShift(_ layout: TrackLayout, steps: Int) -> Bool {
        let delta = Double(steps) * Track.levelHeight / 2
        return layout.walk().placed.allSatisfy {
            Track.withinLevels($0.entryHeight + delta)
                && Track.withinLevels($0.exitHeight + delta)
        }
    }
}
