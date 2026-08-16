import Foundation
import SkidCore

/// **Where a piece's centre-line dashes fall.**
///
/// **Whole dashes inside each piece — gap first, dash last.** The first attempt ran one
/// continuous pattern around the ring and clipped it at the joins, which sounds right and
/// is not: a dash straddling a boundary got drawn twice, once by each piece, and the two
/// halves aliased against each other at the seam. Worse, a piece whose length was not a
/// whole number of periods (every curve, and the start grid) ended mid-dash, so the next
/// road began with a stub.
///
/// Fitting whole dashes per piece removes the problem rather than tuning it. Nothing is
/// clipped, nothing is drawn twice, and every piece ends with a complete dash — so the
/// join between two pieces always falls in a GAP, which is exactly where a seam is
/// invisible.
///
/// The rhythm still reads as continuous because the period is tied to the piece grid: one
/// unit (`U`, also the road width) carries two dashes, and every straight in the catalog
/// is a whole number of units, so consecutive straights share an identical pattern. A
/// curve stretches its period by a few percent to fit whole dashes — imperceptible, and
/// the alternative is the stub this exists to avoid.
enum LaneDashPlan {
    /// Dashes per unit of road. Two, so the pattern divides evenly into every straight
    /// in the catalog (1U, 2U, 4U).
    static let perUnit = 2.0
    /// The nominal length of one dash-plus-gap, before a piece rounds it to fit.
    static var period: Double { Double(PieceCatalog.unit) / perUnit }
    /// How much of a period is painted. Under half, so the mark reads as a road marking
    /// rather than a ladder.
    static let dutyCycle = 0.4
    /// Dash width, as a fraction of the road width.
    static let widthFraction = 0.035

    /// One dash's span along a piece, as start/end fractions of its length.
    struct Dash: Equatable {
        var from: Double
        var to: Double
    }

    /// The dashes for a piece of length `length`.
    ///
    /// Laid out gap-then-dash so the run ends flush with the piece's far edge: the next
    /// piece then opens with a gap, and the seam sits in clear road.
    static func dashes(inPieceOfLength length: Double) -> [Dash] {
        guard length > 0 else { return [] }
        // At least one dash, so a short piece is not left blank.
        let count = max(1, Int((length / period).rounded()))
        let fitted = 1.0 / Double(count)  // one period, as a fraction of the piece
        let dash = fitted * dutyCycle
        return (0..<count).map { index in
            // Each period ENDS with its dash, so the last one finishes at 1.0.
            let end = Double(index + 1) * fitted
            return Dash(from: end - dash, to: end)
        }
    }

    /// Whether a piece carries dashes at all.
    ///
    /// The start-grid piece does not: its own paint (the grid boxes and the line) is
    /// already there, and lane markings would fight it. Nor do gaps and warps, which have
    /// no road to paint.
    static func paints(_ placed: PlacedPiece) -> Bool {
        placed.piece.id != PieceCatalog.startPieceID
            && placed.piece.kind != .gap
            && placed.piece.kind != .warp
    }

    /// Length of a sampled centerline. Local rather than shared: the renderer's copy is
    /// private, and this is four lines.
    static func polylineLength(_ poly: [Vec2]) -> Double {
        guard poly.count > 1 else { return 0 }
        return zip(poly, poly.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
}
