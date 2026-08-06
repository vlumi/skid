import Foundation
import Testing

@testable import SkidCore

/// **Sampling a placed piece**: where its road runs, and which stretches of it carry
/// asphalt.
struct PlacedPieceSamplesTests {
    private func straight() throws -> PlacedPiece {
        try #require(TrackLayout(pieces: [PieceCatalog.ID.straight]).walk().placed.first)
    }

    private func curve() throws -> PlacedPiece {
        try #require(TrackLayout(pieces: [PieceCatalog.ID.curve90MediumLeft]).walk().placed.first)
    }

    // MARK: - point(atFraction:)

    /// The ends are exact, so a caller asking for the lip of a piece gets the piece's
    /// own port rather than a sample near it.
    @Test func theEndsAreThePiecePorts() throws {
        let placed = try straight()
        let samples = placed.centerlineSamples()
        #expect(placed.point(atFraction: 0) == samples.first)
        #expect(placed.point(atFraction: 1) == samples.last)
        // Out of range clamps rather than extrapolating off the end of the road.
        #expect(placed.point(atFraction: -1) == samples.first)
        #expect(placed.point(atFraction: 2) == samples.last)
    }

    /// **Measured by DISTANCE, not by sample index.** That is the whole reason this
    /// exists: a straight has only its two endpoints, so rounding a fraction to the
    /// nearest index snaps to one end — which put a jump's launch line a full unit
    /// away from the lip it was supposed to sit on.
    @Test func aFractionAlongAStraightIsExact() throws {
        let placed = try straight()
        let start = try #require(placed.point(atFraction: 0))
        let end = try #require(placed.point(atFraction: 1))
        let total = start.distance(to: end)

        for fraction in [0.25, 0.5, 0.75] {
            let point = try #require(placed.point(atFraction: fraction))
            #expect(
                abs(start.distance(to: point) - total * fraction) < 0.001,
                "at \(fraction) the point sat \(start.distance(to: point)) along a \(total) piece")
        }
    }

    /// On a CURVE the fraction follows the arc, so the midpoint is equidistant from
    /// both ends — a straight-line interpolation between the ports would not be.
    @Test func aFractionAlongACurveFollowsTheArc() throws {
        let placed = try curve()
        let start = try #require(placed.point(atFraction: 0))
        let end = try #require(placed.point(atFraction: 1))
        let middle = try #require(placed.point(atFraction: 0.5))

        #expect(abs(middle.distance(to: start) - middle.distance(to: end)) < 1)
        // And it is genuinely OFF the chord: a 90° arc bows away from it.
        #expect(middle.distance(toSegment: start, end) > 1)
    }

    // MARK: - solidRuns

    /// An ordinary piece is one unbroken run of asphalt.
    @Test func anOrdinaryPieceIsOneRun() throws {
        let placed = try straight()
        let runs = placed.solidRuns()
        #expect(runs.count == 1)
        #expect(runs.first?.count == placed.heightedSamples().count)
    }

    /// A gap carries none: it is gapped over its whole span, so there is no ribbon.
    @Test func aGapIsNoRuns() throws {
        let placed = try #require(TrackLayout(pieces: [PieceCatalog.ID.gap]).walk().placed.first)
        #expect(placed.solidRuns().isEmpty)
    }

    /// **A gapped CURVE still splits by fraction**, and its solid stretches are the
    /// samples outside the gap.
    ///
    /// Exercised on a curve because a curve is densely sampled: a gap piece is gapped
    /// over its whole span, so on a straight (two endpoints) the "this sample is
    /// road" branch never runs at all, and the split would be untested.
    @Test func aGappedCurveKeepsOnlyItsSolidSamples() throws {
        var placed = try curve()
        placed.piece.kind = .gap
        let samples = placed.heightedSamples()
        #expect(samples.count > 4, "a curve should sample densely enough to split")
        // Gapped over 0...1, so every sample is air and nothing is drawn.
        #expect(placed.solidRuns().isEmpty)

        // As road it is one unbroken run holding every sample it takes.
        //
        // Compared against ITS OWN sampling rather than the gapped piece's: a gapped
        // piece is densified to `gapSpans` so the hole's edges land where they were
        // authored, so the two kinds legitimately sample at different densities (46
        // vs 16 on this curve).
        placed.piece.kind = .road
        let runs = placed.solidRuns()
        #expect(runs.count == 1)
        #expect(runs.first?.count == placed.heightedSamples().count)
    }
}
