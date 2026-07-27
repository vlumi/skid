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

    /// **A ground car under a bridge is never drawn on top of it.** A slope
    /// begins at ground height, so its first sliver is a ramp segment at ~0 and
    /// a car near the foot matched it — promoting a car driving UNDER the bridge
    /// into the elevated pass, where it appeared over the deck. Being off the
    /// ground is the precondition the promotion was missing.
    ///
    /// Mirrors `drawCars`' `onRamp` rule: off the ground, on a ramp, on its road.
    func testGroundCarsAreNeverPromotedToTheDeckPass() {
        let track = TrackLibrary.track(id: "eight")
        var checked = 0
        for index in track.centerline.indices where track.heights[index] <= 0.05 {
            let point = track.centerline[index]
            let height = track.heights[index]
            let promoted =
                height > Track.surfaceTolerance
                && track.isOnRamp(point, height: height)
                && track.distanceToCenterline(point, height: height) <= track.width / 2
            XCTAssertFalse(
                promoted, "ground point \(index) would draw over the bridge")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 20, "the eight should have plenty of ground road")
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
