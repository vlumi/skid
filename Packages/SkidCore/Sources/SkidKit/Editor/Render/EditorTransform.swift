import SkidCore
import SwiftUI

extension EditorRenderer {
    struct Transform {
        /// World space unchanged — for callers whose context is already scaled
        /// and translated (the race view).
        static let identity = Transform(scale: 1, offset: .zero)

        var scale: CGFloat
        var offset: CGSize
        /// Any FURTHER scaling the caller's GraphicsContext applies after
        /// `screen(_:)` — 1 in the editor (whose transform maps all the way to
        /// the screen), the map scale in the race (whose context is scaled to
        /// world units). Quantities that must hold in true screen points
        /// (the seam overlap) divide by this; without it the race shrank the
        /// overlap back under the antialiasing width, and the hairlines the
        /// overlap exists to cover came back — on the rails first, whose
        /// butt-capped ends read crisper than the shaded road fill.
        var contextScale: CGFloat = 1
        func screen(_ p: Vec2) -> CGPoint {
            CGPoint(x: p.x * scale + offset.width, y: p.y * scale + offset.height)
        }

        /// The inverse of `screen(_:)` — a tap, back in world units.
        ///
        /// Hit tests belong in world space: reach is a road width, which is a world
        /// quantity that also grows with height, and converting the road to screen
        /// units per candidate re-derives the same scale over and over.
        func world(_ p: CGPoint) -> Vec2 {
            guard scale != 0 else { return .zero }
            return Vec2((p.x - offset.width) / scale, (p.y - offset.height) / scale)
        }
    }
}
