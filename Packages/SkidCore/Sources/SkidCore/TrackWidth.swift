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
}
