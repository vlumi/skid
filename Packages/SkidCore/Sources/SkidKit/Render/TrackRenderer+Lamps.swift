import SkidCore
import SwiftUI

/// **The car's lamps** — the small white marks that say which end is which, and
/// which way the car is actually traveling.
///
/// Its own file because `TrackRenderer` and `TrackRenderer+Cars` are both at their
/// length budgets, and because these are *marks* rather than car geometry.
///
/// Deliberately small and white. An earlier round replaced the nose sheen with a
/// derived second body tone and it measured worse than one tone: cross-car
/// confusion (any patch of one car against any patch of another) went from ΔE 24.7
/// to 4.6, against the old sheen's 3.7. Large colored areas spend the palette's
/// separation budget; a pair of 3.8-unit dots does not.
extension TrackRenderer {
    /// **The headlight fan — the facing cue.** In the car's own color, so it also
    /// helps tell the cars apart; brightest at the nose, gone by the tip.
    ///
    /// This replaced the two white nose dots: at race zoom they were a couple of
    /// pixels, and reading which end of a smudge carries the dots is not a glance
    /// question. A colored wedge ahead of the car is.
    ///
    /// The fan arrives already clipped (see `Headlight`): walls the car cannot pass
    /// stop it, a covering deck's edge ends it, and the road ahead — ramps included —
    /// never touches it.
    static func drawHeadlight(
        car: CarState, color: Color, track: Track, scale: Double = 1,
        into context: inout GraphicsContext
    ) {
        let fan = Headlight.fan(car: car, track: track, scale: scale)
        guard fan.count > 2 else { return }
        var path = Path()
        path.addLines(fan.map { CGPoint(x: $0.x, y: $0.y) })
        path.closeSubpath()
        let nose = CGPoint(x: fan[0].x, y: fan[0].y)
        context.fill(
            path,
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.5), color.opacity(0)]),
                center: nose, startRadius: 0, endRadius: Headlight.reach * scale))
    }

    /// **Traveling backwards, which is not the same question as facing.**
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
