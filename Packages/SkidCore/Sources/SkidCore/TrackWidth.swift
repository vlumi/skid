import Foundation

/// How wide the road is — which depends on how high it is.
extension Track {
    /// **How far the asphalt reaches from its centerline at `height`.**
    ///
    /// The ribbon is drawn wider as it rises (the fake-perspective `Elevation`
    /// scaling: 1.2× at deck height), and this is the model agreeing with what
    /// it draws. It used to disagree: `width` was flat, so on a bridge a
    /// 12-unit band of painted asphalt — from the nominal edge at 60 out to
    /// the painted one at 72 — was GRASS to the sim. A car there lost grip on
    /// road it could plainly see, and past 60 it "fell off the deck" while
    /// still drawn on it. Teaching each caller to re-apply the scale was the
    /// wrong fix (and one such patch is reverted in favour of this): the road
    /// is wider up there, so the road model says so, once, here.
    public func halfWidth(atHeight height: Double) -> Double {
        width / 2 * Elevation.scale(atHeight: height)
    }

    /// **How far the road's whole visual FOOTPRINT reaches** at `height`: the
    /// asphalt, plus the kerb/rail band that straddles its edge.
    ///
    /// Distinct from `halfWidth`, which is the drivable asphalt. An elevated
    /// road's rails stand on its edge and hide the ground under them exactly
    /// as the asphalt does, so anything reasoning about what the road COVERS
    /// (the under-deck window) needs this, while anything reasoning about what
    /// a car can DRIVE on needs `halfWidth`.
    public func footprintHalfWidth(atHeight height: Double) -> Double {
        halfWidth(atHeight: height) + Double(PieceCatalog.kerbBand)
    }
}
