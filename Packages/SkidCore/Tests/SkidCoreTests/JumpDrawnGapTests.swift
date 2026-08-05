import Foundation
import Testing

@testable import SkidCore

/// **What gets DRAWN, not just what is modelled.** The gap shipped once as real
/// to `surface(at:)` and invisible to every renderer — a jump looked exactly like
/// a straight, which is the "drawing and physics disagree" bug this project keeps
/// paying for. `solidRuns` is the one definition every drawing pass reads, so it
/// is what these pin.
struct JumpDrawnGapTests {
    private func jumpPiece() -> PlacedPiece? {
        TrackLayout(pieces: [PieceCatalog.ID.jump], gateSeams: []).walk().placed.first
    }

    /// A jump draws as TWO ribbons — lip and landing — with nothing between.
    @Test func aJumpDrawsAsTwoSeparateRuns() throws {
        let placed = try #require(jumpPiece())
        let runs = placed.solidRuns()
        #expect(runs.count == 2, "a jump must draw as lip + landing, got \(runs.count) run(s)")
        #expect(runs.allSatisfy { $0.count >= 2 }, "a run needs two points to be a ribbon")
    }

    /// Every ordinary piece still draws as ONE unbroken run — the gap logic must
    /// not nibble at anything else.
    @Test func ordinaryPiecesDrawAsOneRun() {
        for id in [
            PieceCatalog.ID.shortStraight, PieceCatalog.ID.straight,
            PieceCatalog.ID.curve45MediumLeft, PieceCatalog.ID.rampUp,
            PieceCatalog.ID.startGrid,
        ] {
            let placed = TrackLayout(pieces: [id], gateSeams: []).walk().placed.first
            #expect(placed?.solidRuns().count == 1, "piece \(id) should draw as one run")
        }
    }

    /// The drawn hole must line up with the hole the physics uses. Both come from
    /// `gapSpan`, and this is what keeps them honest.
    @Test func theDrawnGapMatchesTheDrivenGap() throws {
        let placed = try #require(jumpPiece())
        let runs = placed.solidRuns()
        #expect(runs.count == 2)
        guard let lipEnd = runs.first?.last, let landingStart = runs.last?.first else { return }

        let span = lipEnd.point.distance(to: landingStart.point)
        // Derived from the piece, not hardcoded: the flagged fraction of its own
        // span. Within one sample step.
        let gap = try #require(placed.piece.gapSpan)
        let expected = Double(PieceCatalog.jumpSpan) * (gap.upperBound - gap.lowerBound)
        #expect(
            abs(span - expected) < Double(PieceCatalog.unit) / 4,
            "drawn hole is \(span) units, the model's is about \(expected)")

        // And the CLEAR air (flagged span minus the two end caps) is at least one
        // road width, so a crossing road fits through the gap.
        let air = span - Double(PieceCatalog.width)
        #expect(
            air >= Double(PieceCatalog.width) - 1,
            "only \(air) units of clear air — a road (width \(PieceCatalog.width)) will not fit")
    }

    /// **A jump is always flat, whatever the build pitch was.**
    ///
    /// Reported from device: a jump laid while the pitch selector sat on "up"
    /// climbed half a level, so the lip and the landing were at different heights
    /// and every piece after it inherited the climb — the track read as "the jump is
    /// just a ramp", and a straight attached after it continued at 1.5.
    @Test func aJumpIgnoresTheBuildPitch() {
        var layout = TrackLayout(
            pieces: [PieceCatalog.ID.startGrid, PieceCatalog.ID.jump, PieceCatalog.ID.straight],
            gateSeams: [])
        layout.pitches = [.flat, .up, .flat]
        let placed = layout.walk().placed
        #expect(placed.count == 3)
        guard placed.count == 3 else { return }

        #expect(placed[1].climb == 0, "the jump climbed \(placed[1].climb)")
        #expect(placed[1].entryHeight == placed[1].exitHeight, "lip and landing differ in height")
        // And nothing downstream inherited a climb that should never have happened.
        #expect(
            placed[2].entryHeight == 0, "the piece after the jump sits at \(placed[2].entryHeight)")
    }

    /// **The crash.** A car in mid-air over the gap matches no road segment at its
    /// height, so `distanceToCenterline` returns `greatestFiniteMagnitude` — and
    /// the debug overlay converted that with `Int(_:)`, which traps. Reported from
    /// the simulator; this pins the value's shape at the source.
    @Test func distanceOverTheGapIsUnboundedRatherThanZero() {
        let track = TestTracks.jumpRing()
        let gapIndices = track.centerline.indices.filter { track.segmentIsGap($0) }
        guard let middle = gapIndices.dropFirst(gapIndices.count / 2).first else {
            Issue.record("no gap")
            return
        }
        // Well above the road, as a launched car is: nothing at this height at all.
        let far = track.distanceToCenterline(track.centerline[middle], height: 0.6)
        #expect(!Track.foundRoad(far), "expected NO road at a mid-air height")
        // `isFinite` is not the guard — the sentinel is finite, and believing
        // otherwise is what crashed the app. Assert that trap explicitly.
        #expect(far.isFinite, "the no-match value is finite; isFinite cannot guard it")

        // On road, the same call is an ordinary number safe to render.
        let onLip = track.distanceToCenterline(track.centerline[0], height: 0)
        #expect(Track.foundRoad(onLip))
        #expect(Int(onLip) >= 0)
    }
}
