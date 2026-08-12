import SkidCore
import SwiftUI

/// **The car's lamps** — the small white marks that say which end is which, and
/// which way the car is actually travelling.
///
/// Its own file because `TrackRenderer` and `TrackRenderer+Cars` are both at their
/// length budgets, and because these are *marks* rather than car geometry.
///
/// Deliberately small and white. An earlier round replaced the nose sheen with a
/// derived second body tone and it measured worse than one tone: cross-car
/// confusion (any patch of one car against any patch of another) went from ΔE 24.7
/// to 4.6, against the old sheen's 3.7. Large coloured areas spend the palette's
/// separation budget; a pair of 3.8-unit dots does not.
extension TrackRenderer {
    /// The lamp dots at the nose tip — flavor at editor zoom, and the only white on
    /// the body. Too small to wash out a palette the way a half-body gradient did.
    static func paintLamps(length: Double, into livery: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            let lamp = CGRect(x: length / 2 - 6, y: side * 3.4 - 1.9, width: 3.8, height: 3.8)
            livery.fill(
                Path(ellipseIn: lamp), with: .color(Color(red: 1, green: 0.98, blue: 0.82)))
        }
    }

    /// **Travelling backwards, which is not the same question as facing.**
    ///
    /// Reported from device: it is easy to reverse by accident and not notice. No
    /// facing cue shows it — a livery and a headlight both say which way the car
    /// *points*, and in a drift game a car often points one way while moving another.
    /// `forwardSpeed` is velocity along the car's own axis, so a negative value is
    /// precisely "going backwards", whatever the throttle is doing.
    ///
    /// Drawn as reversing lamps at the tail, where a driver already looks for them.
    static func paintReverseLamps(
        car: CarState, length: Double, into livery: inout GraphicsContext
    ) {
        guard car.forwardSpeed < -reverseCueSpeed else { return }
        for side in [-1.0, 1.0] {
            let lamp = CGRect(
                x: -length / 2 + 2.2, y: side * 3.4 - 1.9, width: 3.8, height: 3.8)
            livery.fill(Path(ellipseIn: lamp), with: .color(.white.opacity(0.95)))
        }
    }

    /// Below this speed along its own axis, a car is not shown as reversing.
    ///
    /// A car nudging a wall or settling on a slope crosses zero constantly, and a lamp
    /// that flickers with float noise reads as a rendering fault rather than a gear.
    /// 12 units/s is well under `reverseMaxSpeed` (140) but clear of that jitter.
    static let reverseCueSpeed = 12.0
}
