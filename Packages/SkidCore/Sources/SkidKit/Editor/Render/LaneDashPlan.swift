import Foundation
import SkidCore

/// **Where a piece's centre-line dashes fall.**
///
/// **The run is CENTRED in the piece, with half a gap at each end.** A piece of two
/// dashes reads `½gap, dash, gap, dash, ½gap` — so two neighbours contribute half a gap
/// each and the seam carries exactly one normal gap. The rhythm is unbroken across
/// joins, and no dash goes near an edge.
///
/// That last part matters more than it looks. Every piece's asphalt is drawn a hair PAST
/// its own ends (`seamOverlap`, which hides hairline gaps at the joins) and pieces are
/// drawn one after another, so anything painted flush to a boundary gets covered by the
/// next piece's road. Reported from device as alternating dash lengths, always at the
/// seams: measured 3 4 2 4 3 4 3 4 3 pixels along a curve whose dashes are all the same
/// 25.1 units. Centring keeps the paint clear of the overlap by construction, rather
/// than compensating for it.
///
/// Two earlier rules were tried and are worth not repeating: one continuous pattern
/// around the ring, clipped at the joins (a straddling dash was drawn twice, once by
/// each piece, and the halves aliased); and flush-to-the-end dashes (the version that
/// produced the covering above).
///
/// The rhythm still reads as continuous because the period is tied to the piece grid:
/// one unit (`U`, also the road width) carries two dashes, and every straight in the
/// catalog is a whole number of units, so consecutive straights share an identical
/// pattern. A curve stretches its period by a few percent to fit whole dashes.
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

    /// The dashes for a piece of length `length`, centred with half a gap at each end.
    static func dashes(inPieceOfLength length: Double) -> [Dash] {
        guard length > 0 else { return [] }
        // At least one dash, so a short piece is not left blank.
        let count = max(1, Int((length / period).rounded()))
        let fitted = 1.0 / Double(count)  // one period, as a fraction of the piece
        let dash = fitted * dutyCycle
        // Each dash sits in the middle of its own period, which puts half a gap before
        // the first and after the last.
        return (0..<count).map { index in
            let middle = (Double(index) + 0.5) * fitted
            return Dash(from: middle - dash / 2, to: middle + dash / 2)
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
