import SwiftUI

/// **The car body silhouette — one recipe, shared by the game and the app icon.**
///
/// The icon's car drifted out of date once when the in-game body changed and the
/// icon kept the old shape; sharing the path is what makes that structurally
/// impossible rather than a checklist item.
///
/// The shape: square-cornered (matching the menus' pixel look), full width from the
/// tail to midships, then tapered to a narrower nose. The taper replaced the white
/// lamp dots as the body's own facing cue — the silhouette points forward by itself,
/// spending nothing from the color palette's separation budget.
enum CarBody {
    /// The nose corners sit at this fraction of the rear half-width. Subtle on
    /// purpose: enough for the silhouette to point, not enough to read as a wedge.
    static let noseFraction = 0.77

    /// The body outline in the car frame (+x = nose), square-cornered, tapering
    /// from midships to the nose.
    static func path(length: Double, bodyHeight: Double) -> Path {
        let half = length / 2
        let rear = bodyHeight / 2
        let nose = rear * noseFraction
        var path = Path()
        path.addLines([
            CGPoint(x: -half, y: -rear), CGPoint(x: 0, y: -rear),
            CGPoint(x: half, y: -nose), CGPoint(x: half, y: nose),
            CGPoint(x: 0, y: rear), CGPoint(x: -half, y: rear),
        ])
        path.closeSubpath()
        return path
    }
}
