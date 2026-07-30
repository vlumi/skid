import Foundation

/// The overlap gate's REAL metric: how deeply two road ribbons interpenetrate.
/// Split from `RoadProximity` for the length budget; see the notes on
/// `overlapSlack` for why centerline distance alone was the wrong measure.
extension RoadProximity {
    /// **How deeply two ribbons must interpenetrate to count as an overlap.**
    ///
    /// The proximity gate used to be centerline distance against `minGap`
    /// alone, which is calibrated for PARALLEL roads: side by side, centerlines
    /// closer than a road width genuinely share asphalt, and the 0.95 factor
    /// left ~6 units of slack. But centerline distance is direction-blind, and
    /// end-on it overstates wildly — asphalt extends SIDEWAYS from a road, not
    /// off its end. Found on device: a curve ENDING 113.87 from another road's
    /// centerline was refused as an overlap while the drawn ribbons had 41.8
    /// units of clear grass between them, a 0.13-unit shortfall on a metric
    /// measuring the wrong thing. An independent investigation confirmed the
    /// refusal was a false positive and that the first attempt to fix it (the
    /// same-height crossing exemption alone) merely laundered it for whichever
    /// pitch happened to sample near the other road's height.
    ///
    /// So the gate now measures the ribbons themselves: each segment swept to
    /// the road's half-width, penetration depth by separating axes. For
    /// parallel roads this reduces EXACTLY to the old rule (penetration =
    /// width − distance, so the 6-unit slack keeps the same calibration and
    /// the shared-kerb fit at one road width stays legal by threshold); for
    /// end-on approaches it goes to zero where the asphalt is genuinely clear.
    /// `minGap` remains as the cheap broad phase.
    static let overlapSlack = Double(PieceCatalog.width) * 0.05

    /// Penetration depth of two road ribbons: each segment swept perpendicular
    /// to its own half-width, compared by separating axes (exact for
    /// rectangles). 0 when they merely touch or are apart.
    ///
    /// The half-widths are PARAMETERS, defaulted to the nominal road, so the
    /// metric is ready for widths that vary: per-height scaling (an elevated
    /// ribbon is drawn wider — note two decks side by side at one nominal
    /// width of separation visually overlap today, which this could catch once
    /// callers pass `Track.halfWidth(atHeight:)`), and any future
    /// variable-width pieces, which would simply pass per-sample widths. Per
    /// segment is already the right granularity for both.
    static func ribbonPenetration(
        _ a1: Vec2, _ a2: Vec2, _ b1: Vec2, _ b2: Vec2,
        halfWidthA: Double = Double(PieceCatalog.width) / 2,
        halfWidthB: Double = Double(PieceCatalog.width) / 2
    ) -> Double {
        let dirA = a2 - a1
        let dirB = b2 - b1
        guard dirA.length > 1e-9, dirB.length > 1e-9 else {
            // A degenerate segment has no orientation; fall back to the
            // parallel-equivalent bound, which can only over-count.
            let gap = a1.distance(toSegment: b1, b2)
            return max(0, halfWidthA + halfWidthB - gap)
        }
        let axes = [
            dirA.normalized, dirA.normalized.perpendicular,
            dirB.normalized, dirB.normalized.perpendicular,
        ]
        var depth = Double.greatestFiniteMagnitude
        for axis in axes {
            let extentA = halfWidthA * abs(axis.dot(dirA.normalized.perpendicular))
            let extentB = halfWidthB * abs(axis.dot(dirB.normalized.perpendicular))
            let projA = (
                min(a1.dot(axis), a2.dot(axis)) - extentA,
                max(a1.dot(axis), a2.dot(axis)) + extentA
            )
            let projB = (
                min(b1.dot(axis), b2.dot(axis)) - extentB,
                max(b1.dot(axis), b2.dot(axis)) + extentB
            )
            let overlap = min(projA.1, projB.1) - max(projA.0, projB.0)
            if overlap <= 0 { return 0 }
            depth = min(depth, overlap)
        }
        return depth
    }
}
