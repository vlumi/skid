import Foundation
import Testing

@testable import SkidCore

/// **The gap is the feature.** A jump used to be a launch lip over solid road:
/// the car flew, but there was nothing to fall into, so clearing it cost
/// nothing. These pin the hole in the asphalt, and that the centerline running
/// through it is untouched.
struct JumpGapTests {
    @Test func aJumpLeavesAHoleInTheAsphalt() {
        let track = TestTracks.jumpRing()
        #expect(track.gaps.contains(true), "the jump emitted no gap at all")
        #expect(track.gaps.count == track.centerline.count)
    }

    /// The gap must contain real air, and the lip and landing must stay solid.
    ///
    /// Note the asphalt does not end abruptly at the flag: road is "within a
    /// half-width of the centerline", so each lip casts a half-width end cap into
    /// the gap. The air is what survives both caps.
    @Test func thereIsNoRoadAtTheGapButThereIsAtItsEdges() {
        let track = TestTracks.jumpRing()
        let gapIndices = track.centerline.indices.filter { track.segmentIsGap($0) }
        #expect(!gapIndices.isEmpty)

        let air = gapIndices.filter {
            track.surface(at: track.centerline[$0], height: track.height(ofPoint: $0)) == .grass
        }
        #expect(
            !air.isEmpty, "the lips' end caps paved the whole gap — no air to fall into")

        // The lip and the landing are solid — a car has to be ON the lip to
        // launch, and must touch down on something.
        let count = track.centerline.count
        let beforeGap = ((gapIndices.first ?? 0) - 2 + count) % count
        let afterGap = ((gapIndices.last ?? 0) + 2) % count
        #expect(
            track.surface(at: track.centerline[beforeGap], height: track.height(ofPoint: beforeGap))
                == .asphalt, "the launch lip must stay solid")
        #expect(
            track.surface(at: track.centerline[afterGap], height: track.height(ofPoint: afterGap))
                == .asphalt, "the landing must stay solid")
    }

    /// The reason gaps are a parallel flag rather than deleted points: the
    /// runtime's progress, lap scoring and AI all assume one closed loop.
    ///
    /// Asserted against the SAME RING WITHOUT THE JUMP rather than an absolute
    /// stride, because a plain long straight is legitimately 480 units of one
    /// span — comparing to a constant measured the catalog, not the gap.
    @Test func theCenterlineStillRunsThroughTheGap() {
        let withJump = TestTracks.jumpRing()
        let gapped = withJump.centerline.indices.filter { withJump.segmentIsGap($0) }
        #expect(!gapped.isEmpty)

        // Every gap segment is a normal, short stride — points were marked, not
        // dropped. A "delete the points" implementation leaves one long jump here.
        let jumpPieceLength = Double(PieceCatalog.unit * 2)
        for i in gapped {
            let next = (i + 1) % withJump.centerline.count
            let stride = withJump.centerline[i].distance(to: withJump.centerline[next])
            #expect(stride < jumpPieceLength / 2, "a gap-sized stride means points were dropped")
        }

        // Still a closed loop: the last point meets the first.
        if let first = withJump.centerline.first, let last = withJump.centerline.last {
            #expect(last.distance(to: first) < jumpPieceLength)
        } else {
            Issue.record("empty centerline")
        }
    }

    /// **The launch line sits at the lip — the near edge of the gap in the
    /// direction of travel.**
    ///
    /// It used to be built from the piece's `exits[0]`, which is *past the
    /// landing*: a car fell into the gap and was thrown only after it had already
    /// crossed. That was invisible while a "jump" was solid road, and invisible to
    /// every behavioural test here too, since the car still flew — just from the
    /// wrong place. Hence a direct assertion on where the line is.
    @Test func theLaunchLineIsAtTheLipNotPastTheLanding() {
        let track = TestTracks.jumpRing()
        #expect(track.ramps.count == 1, "expected exactly one launch line")
        guard let launch = track.ramps.first else { return }

        let gapIndices = track.centerline.indices.filter { track.segmentIsGap($0) }
        guard let firstGap = gapIndices.first, let lastGap = gapIndices.last else {
            Issue.record("no gap")
            return
        }
        let lip = track.centerline[firstGap]
        let landing = track.centerline[(lastGap + 1) % track.centerline.count]
        let center = (launch.a + launch.b) * 0.5

        #expect(
            center.distance(to: lip) < center.distance(to: landing),
            "the launch line is nearer the LANDING than the lip — a car falls in first")
        // And it is genuinely AT the lip, not merely on the near half. `lip` is the
        // first gap sample, so allow a couple of sample steps rather than a fixed
        // distance — the step scales with the piece's length and sample count.
        let step = Double(PieceCatalog.jumpSpan) / Double(PlacedPiece.gapSpans)
        #expect(
            center.distance(to: lip) <= step * 2,
            "launch line is \(center.distance(to: lip)) from the lip (step \(step))")
    }

    /// **A railed jump gets no railing along its gap.** A fence beside thin air
    /// guards nothing and draws a barrier along a hole; the lip and landing keep
    /// theirs.
    @Test func railingAJumpLeavesTheGapUnfenced() {
        let track = TestTracks.railedJumpRing()
        let gapIndices = track.centerline.indices.filter { track.segmentIsGap($0) }
        guard let firstGap = gapIndices.first, let lastGap = gapIndices.last else {
            Issue.record("no gap")
            return
        }
        let a = track.centerline[firstGap]
        let b = track.centerline[lastGap]
        let alongGap = (b - a)

        // A rail whose midpoint lies beside the gap (projected onto it, and within
        // a road-width across) is a fence along thin air.
        // Laterally within a HALF width of the gap's centerline: that is where this
        // piece's own edge rails would sit. A full width also catches a neighbouring
        // ring's legitimate rails once the gap is long enough to run beside one.
        let offenders = track.walls.filter { wall in
            guard wall.kind == .rail else { return false }
            let mid = (wall.a + wall.b) * 0.5
            let t = (mid - a).dot(alongGap) / alongGap.dot(alongGap)
            guard t > 0.05, t < 0.95 else { return false }
            return mid.distance(toSegment: a, b) <= Double(PieceCatalog.width) / 2 + 1
        }
        #expect(offenders.isEmpty, "\(offenders.count) rail segment(s) run alongside the gap")

        // The rest of the ring still has its railings — suppression is local.
        #expect(track.walls.contains { $0.kind == .rail })
    }

    /// A track with no jump must be byte-for-byte what it was: `gaps` all false.
    @Test func aTrackWithoutAJumpHasNoGaps() {
        let track = TestTracks.steepBridge()
        #expect(track.gaps.allSatisfy { !$0 })
        #expect(!track.gaps.isEmpty)
        #expect(track.gaps.count == track.centerline.count)
    }
}
