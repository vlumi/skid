import Foundation
import Testing

@testable import SkidCore

/// **What a track is, as numbers** — for the author while building and for the
/// catalogue when choosing. Measured off the layout, so a corner is what the
/// catalog says it is rather than something re-derived from a polyline.
struct TrackStatsTests {
    private func stats(_ pieces: [PieceID]) throws -> TrackStats {
        try #require(TrackStats.of(layout: TrackLayout(pieces: pieces)))
    }

    /// **Length agrees with the compiled centerline**, which is the one number
    /// something else already computes — so if these two ever disagree, one of
    /// them is lying about the road the car drives.
    @Test func lengthMatchesTheCompiledCenterline() throws {
        for builtin in TrackLibrary.builtins {
            let layout = try TrackCode.decode(builtin.code)
            let measured = try #require(TrackStats.of(layout: layout))
            let compiled = TrackLibrary.track(id: builtin.id).centerlineLength
            #expect(
                abs(measured.length - compiled) < 1,
                "\(builtin.name): stats say \(measured.length), the track says \(compiled)")
        }
    }

    /// **A corner is a turn a DRIVER takes, not an arc piece.** Four 45° sweeps
    /// in a row are one long corner; counting four would make every flowing oval
    /// read as a technical track.
    @Test func consecutiveArcsOneWayAreOneCorner() throws {
        let sweep = PieceCatalog.ID.curve45SweepRight
        let measured = try stats([PieceCatalog.startPieceID, sweep, sweep, sweep, sweep])
        #expect(measured.corners == 1)
        #expect(measured.rightCorners == 1)
        #expect(measured.leftCorners == 0)
        #expect(measured.totalTurnDegrees == 180)
    }

    /// Changing direction starts a new corner, which is what makes an S an S.
    @Test func turningTheOtherWayStartsANewCorner() throws {
        let left = PieceCatalog.ID.curve90MediumLeft
        let right = PieceCatalog.ID.curve90MediumRight
        let measured = try stats([PieceCatalog.startPieceID, left, right, left])
        #expect(measured.corners == 3)
        #expect(measured.leftCorners == 2)
        #expect(measured.rightCorners == 1)
        #expect(measured.totalTurnDegrees == 270)
    }

    /// A straight between two bends the same way separates them — otherwise a
    /// lap round a square would count as one corner.
    @Test func aStraightSeparatesTwoCornersTheSameWay() throws {
        let right = PieceCatalog.ID.curve90MediumRight
        let straight = PieceCatalog.ID.straight
        let measured = try stats([PieceCatalog.startPieceID, right, straight, right])
        #expect(measured.corners == 2)
        #expect(measured.rightCorners == 2)
    }

    /// **A straight is a continuous run**, across as many pieces as it takes —
    /// counting one per piece made a 16-piece track report 16 straights, which
    /// says nothing about whether there is anywhere to use top speed.
    @Test func straightsAreRunsNotPieces() throws {
        let short = PieceCatalog.ID.shortStraight
        let right = PieceCatalog.ID.curve90MediumRight
        let measured = try stats(
            [PieceCatalog.startPieceID, short, short, short, right, short, short])
        #expect(measured.straightCount == 2, "a run of pieces is one straight")
        // Run one is the start piece plus three shorts; run two is two shorts.
        // The longest is therefore the FIRST run, and it is the sum of its
        // pieces rather than any single piece's length.
        #expect(measured.longestStraight == 600)
    }

    /// **The tightest CORNER, not the tightest arc.** A 45° flick at a small
    /// radius is a kink; letting one set this made a flowing track read as
    /// tighter than its own hairpins.
    @Test func theTightestRadiusIgnoresMereKinks() throws {
        let hairpin = PieceCatalog.ID.hairpinMediumLeft
        let flick = PieceCatalog.ID.curve45TightRight
        let straight = PieceCatalog.ID.straight
        let measured = try stats(
            [PieceCatalog.startPieceID, hairpin, straight, flick, straight])
        let hairpinRadius = try #require(
            radius(of: PieceCatalog.ID.hairpinMediumLeft))
        #expect(
            measured.tightestRadius == hairpinRadius,
            "a 45° flick was reported as the tightest corner")
    }

    /// A track with nothing but kinks still reports one, rather than nil — the
    /// number should not vanish on a track that does bend.
    @Test func aTrackOfOnlyKinksStillReportsARadius() throws {
        let flick = PieceCatalog.ID.curve45TightRight
        let straight = PieceCatalog.ID.straight
        let measured = try stats([PieceCatalog.startPieceID, flick, straight, flick])
        #expect(measured.tightestRadius != nil)
    }

    @Test func aStraightTrackHasNoCornersAndNoRadius() throws {
        let measured = try stats(
            [PieceCatalog.startPieceID, PieceCatalog.ID.straight, PieceCatalog.ID.straight])
        #expect(measured.corners == 0)
        #expect(measured.tightestRadius == nil)
        #expect(measured.totalTurnDegrees == 0)
        #expect(measured.cornersPerKilounit == 0)
    }

    /// Climb counts every rise, so a lap that goes up and down twice reports
    /// more than its top level — which is the number that says how hilly it is.
    @Test func climbCountsEveryRiseNotJustTheHighestPoint() throws {
        let eight = try #require(TrackLibrary.builtins.first { $0.id == "eight" })
        let clover = try #require(TrackLibrary.builtins.first { $0.id == "clover" })
        let flat = try #require(TrackLibrary.builtins.first { $0.id == "oval" })
        let eightStats = try #require(TrackStats.of(layout: try TrackCode.decode(eight.code)))
        let cloverStats = try #require(TrackStats.of(layout: try TrackCode.decode(clover.code)))
        let flatStats = try #require(TrackStats.of(layout: try TrackCode.decode(flat.code)))
        #expect(flatStats.topLevel == 0)
        #expect(flatStats.totalClimb == 0)
        #expect(eightStats.topLevel >= 1)
        // The clover climbs repeatedly, so its total exceeds its top level.
        #expect(cloverStats.totalClimb > Double(cloverStats.topLevel))
    }

    /// Corners per 1000 units is the "twisty" number, since twistiness is a
    /// ratio: the clover is longer than the small track but less busy per unit.
    @Test func twistinessIsARatioNotACount() throws {
        let small = try #require(
            TrackStats.of(
                layout: try TrackCode.decode(
                    TrackLibrary.builtins.first { $0.id == "small" }!.code)))
        let oval = try #require(
            TrackStats.of(
                layout: try TrackCode.decode(
                    TrackLibrary.builtins.first { $0.id == "oval" }!.code)))
        #expect(small.cornersPerKilounit > oval.cornersPerKilounit)
    }

    // MARK: - The pieces no built-in uses yet

    /// **A gap interrupts a straight**, which is the whole point of one: the run
    /// before it and the run after it are two straights, not one long one with a
    /// hole. No built-in has a jump yet, so this branch is only reachable from a
    /// hand-built layout — and it is exactly the case an author testing jumps
    /// would hit first.
    @Test func aGapBreaksAStraightInTwo() throws {
        let straight = PieceCatalog.ID.straight
        let solid = try stats([PieceCatalog.startPieceID, straight, straight])
        #expect(solid.straightCount == 1, "an unbroken run is one straight")

        let jumped = try stats([PieceCatalog.startPieceID, straight, PieceCatalog.ID.gap, straight])
        #expect(jumped.straightCount == 2, "the gap did not break the run")
        // The gap itself is not road, so it adds no corners and no turn.
        #expect(jumped.corners == 0)
        #expect(jumped.totalTurnDegrees == 0)
    }

    /// **A fitter's length counts; its bends do not.** The piece exists to close
    /// a gap the catalog cannot, and its curvature is a consequence of that
    /// rather than a corner somebody designed — calling it one would inflate the
    /// count on any track that used a fitter to join up.
    @Test func aFittersLengthCountsButItsBendsAreNotCorners() throws {
        var layout = TrackLayout(pieces: [PieceCatalog.startPieceID, PieceCatalog.ID.straight])
        let withoutFitter = try #require(TrackStats.of(layout: layout))

        layout.pieces.append(PieceCatalog.fitterPieceID)
        layout.fitters[layout.pieces.count - 1] = Fitter(
            radius: 120, angle: 0.4, length: 240, stepsLeft: true)
        let withFitter = try #require(TrackStats.of(layout: layout))

        #expect(
            withFitter.length > withoutFitter.length,
            "the fitter contributed no length")
        #expect(
            withFitter.corners == withoutFitter.corners,
            "a fitter's bend was counted as a corner")
    }

    /// A partial track is still worth measuring — the editor shows these while
    /// the road has a loose end.
    @Test func anUnfinishedTrackStillMeasures() throws {
        let measured = try stats([PieceCatalog.startPieceID])
        #expect(measured.length > 0)
        #expect(measured.pieceCount == 1)
    }

    /// The radius the catalog states for a piece, for tests that need to name
    /// one without hardcoding a number that could drift.
    private func radius(of id: PieceID) -> Double? {
        guard let piece = PieceCatalog.all[id] else { return nil }
        for segment in piece.paths.first ?? [] {
            if case .arc(let radius, _, _) = segment { return Double(Coord(radius).value) }
        }
        return nil
    }
}
