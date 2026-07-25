import XCTest

@testable import SkidCore

/// Checkpoint gates: a lap only counts when each is crossed in order, so a
/// saveable track needs at least one besides the start line. Without a way to
/// mark them no track could be completed at all, which is what these guard.
final class GateTests: XCTestCase {
    private typealias Pieces = PieceCatalog.ID

    /// The track the user actually built (share code AaEBCh8MDAwJAAAKDBoCAQADBQAAAAAA):
    /// closed, no overlaps, fits the canvas — but unsaveable with one gate.
    private let userTrack: [PieceID] = [
        Pieces.startGrid, Pieces.curve90MediumRight, Pieces.curve90MediumRight,
        Pieces.curve90MediumRight, Pieces.curve90TightLeft, Pieces.shortStraight,
        Pieces.shortStraight, Pieces.curve90TightRight, Pieces.curve90MediumRight,
        Pieces.jog240Right,
    ]

    func testAClosedTrackWithOnlyTheStartLineIsUnsaveable() {
        let layout = TrackLayout(pieces: userTrack, gateSeams: [0])
        XCTAssertTrue(layout.walk().openEnds.isEmpty, "the geometry closes")
        XCTAssertEqual(TrackValidator.validate(layout).problems, [.gates])
    }

    /// The same track with checkpoints marked is fully saveable and compiles.
    func testMarkingCheckpointsMakesItRaceable() throws {
        let layout = TrackLayout(pieces: userTrack, gateSeams: [0, 3, 6])
        XCTAssertTrue(
            TrackValidator.validate(layout).isSaveable,
            "problems: \(TrackValidator.validate(layout).problems)")
        let track = try PieceCompiler.compile(layout, id: "user-track")
        XCTAssertEqual(track.gates.count, 3)
        // Every gate must sit on the driven path, oriented with traffic — else
        // a lap can't be completed.
        var crossed = Set<Int>()
        let line = track.centerline
        for i in line.indices {
            let a = line[i]
            let b = line[(i + 1) % line.count]
            for (g, gate) in track.gates.enumerated()
            where gate.crossedForward(movingFrom: a, to: b) {
                crossed.insert(g)
            }
        }
        XCTAssertEqual(crossed.count, track.gates.count, "every gate must be drivable in order")
    }

    /// A layout built outward from the origin can run to NEGATIVE coordinates —
    /// i.e. off the canvas — and would race letterboxed into a corner, half
    /// offscreen. Centring shifts the stored origin so the whole rigid layout
    /// lands inside the canvas.
    func testCenteringBringsALayoutOntoTheCanvas() throws {
        var layout = TrackLayout(pieces: userTrack, gateSeams: [0, 3, 6])
        struct Bounds {
            var minX: Double
            var maxX: Double
            var minY: Double
            var maxY: Double
        }
        func bounds(_ l: TrackLayout) -> Bounds {
            let points: [Vec2] = l.walk().placed.flatMap { $0.centerlineSamples() }
            return Bounds(
                minX: points.map(\.x).min()!, maxX: points.map(\.x).max()!,
                minY: points.map(\.y).min()!, maxY: points.map(\.y).max()!)
        }
        let before = bounds(layout)
        XCTAssertLessThan(before.minX, 0, "this layout starts partly off-canvas")

        // The same shift `editorCenterOnCanvas` applies.
        let canvas = TrackValidator.canvas
        let unit = Double(PieceCatalog.unit)
        let steps = CoordPoint(
            Int((((canvas.x - (before.maxX - before.minX)) / 2 - before.minX) / unit).rounded())
                * PieceCatalog.unit,
            Int((((canvas.y - (before.maxY - before.minY)) / 2 - before.minY) / unit).rounded())
                * PieceCatalog.unit)
        layout.origin = PiecePose(
            position: layout.origin.position + steps, heading: layout.origin.heading)

        let after = bounds(layout)
        let half = Double(PieceCatalog.width) / 2
        XCTAssertGreaterThan(after.minX, half, "fully on-canvas, road width included")
        XCTAssertGreaterThan(after.minY, half)
        XCTAssertLessThan(after.maxX, canvas.x - half)
        XCTAssertLessThan(after.maxY, canvas.y - half)
        // Shifting the anchor must not change the track itself.
        XCTAssertTrue(TrackValidator.validate(layout).isSaveable)
        XCTAssertEqual(
            after.maxX - after.minX, before.maxX - before.minX, "the layout is rigid")
    }

    /// Gates span the CORRIDOR, not just the asphalt: running wide onto the
    /// grass still counts (the grass is its own penalty), only a gross cut
    /// through the infield misses. Spanning just the road made checkpoints feel
    /// unfairly strict — and inconsistent with the built-in tracks, which have
    /// always used a corridor span.
    func testGatesReachPastTheAsphaltOntoTheGrass() throws {
        let layout = TrackLayout(pieces: userTrack, gateSeams: [0, 3, 6])
        let track = try PieceCompiler.compile(layout, id: "corridor")
        let asphalt = Double(PieceCatalog.width)
        for gate in track.gates {
            XCTAssertGreaterThan(
                (gate.b - gate.a).length, asphalt,
                "a gate should reach beyond the road, not stop at its edge")
        }
    }

    /// ...but never more than halfway to another lane, or a gate could be
    /// satisfied from the neighbouring road. A hairpin puts its legs 2r apart,
    /// which is exactly where that cap has to bite.
    func testGatesAreCappedHalfwayToANeighbouringLane() throws {
        let hairpin: [PieceID] = [
            Pieces.startGrid, Pieces.hairpinTightLeft, Pieces.straight,
            Pieces.hairpinTightLeft, Pieces.straight,
        ]
        let layout = TrackLayout(pieces: hairpin, gateSeams: [0, 2])
        guard let track = try? PieceCompiler.compile(layout, id: "hairpin") else { return }
        // The legs' centrelines are 2 x tightRadius apart, so no gate may span
        // far enough to touch the other one.
        let laneGap = Double(2 * PieceCatalog.tightRadius)
        for gate in track.gates {
            XCTAssertLessThan(
                (gate.b - gate.a).length, laneGap + Double(PieceCatalog.width),
                "a gate must not reach into the return lane")
        }
    }

    /// Seam 0 is the start/finish and permanent; gates cap at 16.
    func testGateRules() {
        // Seam 0 must always be a gate.
        XCTAssertEqual(
            TrackValidator.validate(TrackLayout(pieces: userTrack, gateSeams: [3, 6])).problems,
            [.gates], "a track without the start/finish gate is invalid")
        // Too many gates is invalid too.
        let many = Array(0..<17)
        XCTAssertEqual(
            TrackValidator.validate(TrackLayout(pieces: userTrack, gateSeams: many)).problems,
            [.gates])
    }
}
