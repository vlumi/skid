import XCTest

@testable import SkidCore
@testable import SkidKit

/// What belongs to which height band. The race view draws the ground, then the
/// cars, then the bridge over them — so anything painted in the wrong band
/// shows through the deck.
final class RenderBandTests: XCTestCase {
    /// The two bands the race view draws, split at half a level.
    private let ground = -1.0...0.5
    private let elevated = 0.5...2.0

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

    /// **At a crossing, the higher seam wins the tap.** Two seams can sit at
    /// the same screen point where a bridge crosses a road; the deck one is
    /// drawn on top, so it's what the author is pointing at. Flat 2D distance
    /// alone gave it to whichever came first in the piece list — the road
    /// underneath — which made a gate on the bridge impossible to toggle.
    ///
    /// Mirrors `EditorView.seam(near:)`'s rule without a view.
    func testTheHigherSeamWinsAtACrossing() throws {
        let layout = try XCTUnwrap(TrackLibrary.layout(id: "eight"))
        let placed = layout.walk().placed
        // Find two seams (piece exits) that share a spot at different heights.
        var overlapping: (low: Int, high: Int)?
        for (i, a) in placed.enumerated() where i != 0 {
            for (j, b) in placed.enumerated() where j != 0 && j != i {
                let apart = a.exits[0].position.vec2.distance(to: b.exits[0].position.vec2)
                guard apart < 40, abs(a.exitHeight - b.exitHeight) > 0.4 else { continue }
                overlapping =
                    a.exitHeight < b.exitHeight ? (low: i, high: j) : (low: j, high: i)
            }
        }
        let pair = try XCTUnwrap(overlapping, "the eight should cross itself at two heights")
        // Run the tie-break itself, in the order that used to lose: the lower
        // seam offered first, so "whichever came first" would pick it.
        let hitRadius = 30.0
        let ordered = [pair.low, pair.high]
        var best: (seam: Int, distance: Double)?
        var bestHeight = -Double.infinity
        let tap = placed[pair.high].exits[0].position.vec2
        for index in ordered {
            let distance = placed[index].exits[0].position.vec2.distance(to: tap)
            guard distance < hitRadius else { continue }
            let height = placed[index].exitHeight
            guard let current = best else {
                best = (index, distance)
                bestHeight = height
                continue
            }
            let muchNearer = distance < current.distance - hitRadius / 2
            let higher = height > bestHeight + 0.001 && distance < current.distance + hitRadius / 2
            if muchNearer || higher {
                best = (index, distance)
                bestHeight = height
            }
        }
        XCTAssertEqual(
            best?.seam, pair.high,
            "the seam on the bridge must win the tap, not the road underneath")
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
