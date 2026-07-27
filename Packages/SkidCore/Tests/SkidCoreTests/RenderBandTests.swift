import XCTest

@testable import SkidCore
@testable import SkidKit

/// What belongs to which height band. The race view draws the ground, then the
/// cars, then the bridge over them — so anything painted in the wrong band
/// shows through the deck.
final class RenderBandTests: XCTestCase {
    /// The two bands the race view draws. They PARTITION: piece heights sit
    /// on the half-level lattice (maxima 0, 0.5 or 1), and 0.75 separates
    /// "reaches above the shelf" from "stays at or below it". When the bands
    /// overlapped at exactly 0.5, every climb's lower half drew in both passes
    /// and its second copy buried the car on it.
    private let ground = -1.0...0.5
    private let elevated = 0.75...2.0

    /// **The start line and grid are paint on the start piece's own road**, so
    /// they draw in that piece's band and no other. Both ends have to be inside
    /// it: testing only the exit let a ground-level start line paint during the
    /// elevated pass, showing through a bridge that crosses over it.
    func testTheStartPieceBelongsToExactlyOneBand() throws {
        for id in ["small", "oval", "eight"] {
            let layout = try XCTUnwrap(TrackLibrary.layout(id: id))
            let start = try XCTUnwrap(
                layout.walk().placed.first { $0.id == PieceCatalog.startPieceID })
            let inGround =
                ground.contains(start.entryHeight) && ground.contains(start.exitHeight)
            let inElevated =
                elevated.contains(start.entryHeight) && elevated.contains(start.exitHeight)
            XCTAssertNotEqual(
                inGround, inElevated,
                "\(id): the start piece must draw in exactly one band")
        }
    }

    /// **Only a coincident pair is decided by height; otherwise nearest wins.**
    ///
    /// Where a bridge crosses a road, two seams can sit at the same screen point
    /// — distance can't choose, so the one drawn on top does. But a tap plainly
    /// nearer the lower seam must toggle THAT one: a wide tie-break window made
    /// the bridge win everywhere, and the gate underneath became unremovable.
    ///
    /// Mirrors `EditorView.seam(near:)`'s rule without a view.
    func testHeightBreaksOnlyExactTies() throws {
        let layout = try XCTUnwrap(TrackLibrary.layout(id: "eight"))
        let placed = layout.walk().placed
        var pair: (low: Int, high: Int)?
        for (i, a) in placed.enumerated() where i != 0 {
            for (j, b) in placed.enumerated() where j != 0 && j != i {
                let apart = a.exits[0].position.vec2.distance(to: b.exits[0].position.vec2)
                guard apart < 1, abs(a.exitHeight - b.exitHeight) > 0.4 else { continue }
                pair = a.exitHeight < b.exitHeight ? (low: i, high: j) : (low: j, high: i)
            }
        }
        let crossing = try XCTUnwrap(pair, "the eight should cross itself at one point")

        // Tapping the shared point: the bridge wins, even offered second.
        XCTAssertEqual(
            pick(among: [crossing.low, crossing.high], tapping: crossing.high, in: placed),
            crossing.high, "at the same spot, the higher seam wins")

        // Tapping a DIFFERENT seam nearby: nearest wins, height notwithstanding.
        let other = try XCTUnwrap(
            placed.indices.first {
                $0 != 0 && $0 != crossing.low && $0 != crossing.high
                    && placed[$0].exitHeight < 0.4
            }, "the eight should have ground seams elsewhere")
        XCTAssertEqual(
            pick(among: [crossing.high, other], tapping: other, in: placed), other,
            "a tap aimed at a ground seam must not be stolen by the bridge")
    }

    /// The hit-test's choice among candidate seams, given a tap at `tapping`'s
    /// own position — the same rule `EditorView.seam(near:)` applies.
    private func pick(among seams: [Int], tapping: Int, in placed: [PlacedPiece]) -> Int? {
        let tap = placed[tapping].exits[0].position.vec2
        var best: (seam: Int, distance: Double)?
        var bestHeight = -Double.infinity
        for index in seams {
            let distance = placed[index].exits[0].position.vec2.distance(to: tap)
            guard distance < 26 else { continue }
            let height = placed[index].exitHeight
            guard let current = best else {
                best = (index, distance)
                bestHeight = height
                continue
            }
            let coincident = abs(distance - current.distance) < 1
            let takes = coincident ? height > bestHeight + 0.001 : distance < current.distance
            if takes {
                best = (index, distance)
                bestHeight = height
            }
        }
        return best?.seam
    }

    /// **The car interleave assumes two storeys — this trips when that ends.**
    /// The race view draws ground ribbons, ground cars, elevated ribbons, then
    /// everything else; the general rule (a ribbon covers only cars a full
    /// level below it) collapses to that single split ONLY while the world has
    /// storeys 0 and 1. Raising `highestLevel` (the rollercoaster) needs
    /// per-storey interleaving of ribbon and car passes first — see the plan in
    /// docs/track-pieces.md.
    func testTheCarInterleaveMatchesTheWorldsStoreys() {
        XCTAssertEqual(
            Track.highestLevel, 1,
            "add per-storey render passes before raising the world's ceiling")
    }

    /// **Every piece draws in exactly one pass.** In both is a double-draw
    /// whose second copy buries the cars on that piece; in neither is a hole in
    /// the road. This is the invariant behind two shipped artifacts: a ground
    /// car riding on top of the bridge, and a climber hidden under the foot of
    /// its own ramp.
    func testTheBandsPartitionEveryPiece() throws {
        for id in ["small", "oval", "eight"] {
            let layout = try XCTUnwrap(TrackLibrary.layout(id: id))
            for piece in layout.walk().placed {
                let top = max(piece.entryHeight, piece.exitHeight)
                let inGround = ground.contains(top)
                let inElevated = elevated.contains(top)
                XCTAssertNotEqual(
                    inGround, inElevated,
                    "\(id): piece topping at \(top) must draw in exactly one pass")
            }
        }
    }

    /// A crossing exists on the eight at both heights — the case where a
    /// misbanded start line would be visible — so the fixture really exercises
    /// the rule rather than passing for lack of a bridge.
    func testTheEightHasRoadAtBothBands() throws {
        let layout = try XCTUnwrap(TrackLibrary.layout(id: "eight"))
        let placed = layout.walk().placed
        XCTAssertTrue(placed.contains { ground.contains($0.entryHeight) })
        XCTAssertTrue(placed.contains { elevated.contains($0.exitHeight) })
    }
}
