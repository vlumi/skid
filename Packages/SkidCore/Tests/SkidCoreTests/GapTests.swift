import Foundation
import Testing

@testable import SkidCore

/// **A gap is absence of road** — nothing more. It has no height effect and no
/// launch of its own: a car flies over one because it drove off a wedge, and lands
/// wherever a `warp` put the road.
///
/// These assert on what gets DRAWN as well as what gets driven. An earlier version
/// of this feature was real to `surface(at:)` and invisible to every renderer, so a
/// jump looked exactly like a straight — the drawing and the physics disagreeing,
/// which is this project's most expensive recurring bug.
struct GapTests {
    private func gapPiece() -> PlacedPiece? {
        TrackLayout(pieces: [PieceCatalog.ID.gap]).walk().placed.first
    }

    /// The whole piece is gap, so it draws as nothing at all.
    @Test func aGapDrawsNothing() throws {
        let placed = try #require(gapPiece())
        #expect(placed.piece.gapSpan == 0...1)
        #expect(placed.solidRuns().isEmpty, "a gap must contribute no ribbon")
    }

    /// Every ordinary piece still draws as ONE unbroken run — the gap logic must
    /// not nibble at anything else.
    @Test func ordinaryPiecesDrawAsOneRun() {
        for id in [
            PieceCatalog.ID.shortStraight, PieceCatalog.ID.straight,
            PieceCatalog.ID.curve45MediumLeft, PieceCatalog.ID.startGrid,
        ] {
            let placed = TrackLayout(pieces: [id]).walk().placed.first
            #expect(placed?.solidRuns().count == 1, "piece \(id) should draw as one run")
        }
    }

    /// A gap has **no height effect**: what moves the road between levels is a warp.
    @Test func aGapDoesNotChangeHeight() throws {
        let placed = try #require(gapPiece())
        #expect(placed.climb == 0)
        #expect(placed.piece.heightDelta == 0)
    }

    /// **There is real air over a gap**, so a car can be off the road there.
    ///
    /// Worth pinning because it nearly wasn't: asphalt reaches a half-width past the
    /// last solid point, and a zero-length warp used to stamp a pile of duplicate
    /// centerline points beside the gap — each casting its own end cap, which paved
    /// the hole over completely and left the car "on road" across it.
    @Test func thereIsAirOverAGap() {
        let track = TestTracks.jumpRing()
        let gapPoints = track.centerline.indices.filter { track.segmentIsGap($0) }
        #expect(!gapPoints.isEmpty, "the ring should have a gap at all")

        let lipHeight = gapPoints.first.map { track.height(ofPoint: $0) } ?? 0
        let air = gapPoints.filter {
            let distance = track.distanceToCenterline(
                track.centerline[$0], height: lipHeight)
            return !Track.foundRoad(distance) || distance > track.halfWidth(atHeight: lipHeight)
        }
        #expect(!air.isEmpty, "the gap is entirely paved — a car could never leave the road")
    }

    /// The centerline runs THROUGH a gap, so progress, lap scoring and the AI need
    /// to know nothing about it. Deleting the points instead would break the loop.
    @Test func theCenterlineStillRunsThroughAGap() {
        let track = TestTracks.jumpRing()
        let gapped = track.centerline.indices.filter { track.segmentIsGap($0) }
        #expect(!gapped.isEmpty)
        for i in gapped {
            let next = (i + 1) % track.centerline.count
            let stride = track.centerline[i].distance(to: track.centerline[next])
            #expect(
                stride < Double(PieceCatalog.unit),
                "a gap-sized stride means points were dropped")
        }
    }

    /// A track with no gap is unchanged: `gaps` all false.
    @Test func aTrackWithoutAGapHasNoGaps() {
        let track = TestTracks.steepBridge()
        #expect(!track.gaps.isEmpty)
        #expect(track.gaps.allSatisfy { !$0 })
        #expect(track.gaps.count == track.centerline.count)
    }

    /// **A railed gap gets no railing.** A fence beside thin air guards nothing.
    @Test func railingAGapLeavesItUnfenced() {
        let track = TestTracks.railedJumpRing()
        let gapPoints = track.centerline.indices.filter { track.segmentIsGap($0) }
        guard let first = gapPoints.first, let last = gapPoints.last else {
            Issue.record("no gap")
            return
        }
        let a = track.centerline[first]
        let b = track.centerline[last]
        let along = b - a

        let offenders = track.walls.filter { wall in
            guard wall.kind == .rail else { return false }
            let mid = (wall.a + wall.b) * 0.5
            let t = (mid - a).dot(along) / along.dot(along)
            guard t > 0.05, t < 0.95 else { return false }
            return mid.distance(toSegment: a, b) <= Double(PieceCatalog.width) / 2 + 1
        }
        #expect(offenders.isEmpty, "\(offenders.count) rail segment(s) run alongside the gap")
        #expect(track.walls.contains { $0.kind == .rail }, "the rest of the ring keeps its rails")
    }

    /// A zero-length piece contributes **no centerline points**. This is what stops
    /// a warp paving the gap beside it.
    @Test func aWarpContributesNoRoad() throws {
        typealias Catalog = PieceCatalog.ID
        let withWarp = TrackLayout(
            pieces: [Catalog.startGrid, Catalog.shortStraight, Catalog.warp])
        let without = TrackLayout(pieces: [Catalog.startGrid, Catalog.shortStraight])

        // Compile-free comparison: the walk's own samples, as the compiler lowers
        // them (it skips warps entirely).
        func points(_ layout: TrackLayout) -> Int {
            layout.walk().placed.filter { $0.piece.kind != .warp }
                .reduce(0) { $0 + $1.heightedSamples().count }
        }
        #expect(points(withWarp) == points(without))
    }
}

/// **Hiding the editor's controls must not narrow the format.**
///
/// The Gap piece and the warp arrows sit behind a build flag because *editing* them
/// is the doubtful part — a warp is invisible and a gap is a piece made of nothing.
/// The pieces themselves are not in doubt, and a track built with them has to keep
/// working on a build that cannot author one: it may arrive as a share code from
/// someone else's device.
struct ExperimentalGapsStayRaceableTests {
    /// The catalog knows both pieces regardless of what the editor offers.
    @Test func theCatalogAlwaysCarriesGapsAndWarps() throws {
        let gap = try #require(PieceCatalog.piece(PieceCatalog.ID.gap))
        let warp = try #require(PieceCatalog.piece(PieceCatalog.ID.warp))
        #expect(gap.kind == .gap)
        #expect(warp.kind == .warp)
    }

    /// A code carrying them decodes with both intact — including the warp's drop,
    /// which is the part a "just hide the buttons" change could plausibly break.
    @Test func aTrackUsingThemRoundTripsThroughTheShareCode() throws {
        var layout = try #require(TestTracks.jumpRing().layout)
        let warpIndex = try #require(layout.pieces.firstIndex(of: PieceCatalog.ID.warp))
        layout.warpDrops[warpIndex] = -Track.levelHeight

        let back = try TrackCode.decode(TrackCode.encode(layout))
        #expect(back.pieces.contains(PieceCatalog.ID.gap))
        #expect(back.pieces.contains(PieceCatalog.ID.warp))
        let decodedWarp = try #require(back.pieces.firstIndex(of: PieceCatalog.ID.warp))
        #expect(back.warpDrop(at: decodedWarp) == -Track.levelHeight)
    }

    /// And it still races: the AI laps it, and the car really leaves the road.
    @Test func aTrackUsingThemStillRaces() {
        let track = TestTracks.jumpRing()
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
        var driver = AIDriver()
        var airborne = 0
        for _ in 0..<(60 * Race.tickRate) {
            race.advance(
                inputs: [PlayerID(0): driver.input(car: race.cars[0].state, track: track)])
            if race.cars[0].state.isAirborne { airborne += 1 }
            if race.cars[0].progress.finishedAt != nil { break }
        }
        #expect(race.cars[0].progress.finishedAt != nil, "a gapped track must be lappable")
        #expect(airborne > 0, "and the gap must still be a gap")
    }
}
