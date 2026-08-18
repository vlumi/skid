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
    /// The countdown's "this one is yours": a round highlight of the player's
    /// color under their car, tethered by a thin leader line to their control
    /// band. Registered as `.halo`, so the CARS genuinely paint on top — the
    /// first cut drew these in the screen-space overlay, where translucency only
    /// faked "under". Two passes — every line, then every halo — so a line
    /// crossing the packed grid to a far car passes beneath the other players'
    /// halos too. `pixelScale` is the world→screen factor: sizes divide by it,
    /// so a halo is 11 SCREEN points on every track.
    static func drawGridMarkers(
        _ markers: [GridMarker], pixelScale: Double, into context: inout GraphicsContext
    ) {
        let radius = 11.0 / pixelScale
        for marker in markers {
            let toCar = marker.position - marker.leaderStart
            guard toCar.length > radius + 1 else { continue }
            let end = marker.position - toCar.normalized * radius
            var line = Path()
            line.move(to: CGPoint(x: marker.leaderStart.x, y: marker.leaderStart.y))
            line.addLine(to: CGPoint(x: end.x, y: end.y))
            context.stroke(
                line, with: .color(marker.color.opacity(0.55)),
                lineWidth: 2.0 / pixelScale)
        }
        for marker in markers {
            let disc = CGRect(
                x: marker.position.x - radius, y: marker.position.y - radius,
                width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: disc), with: .color(marker.color.opacity(0.3)))
            context.stroke(
                Path(ellipseIn: disc), with: .color(marker.color.opacity(0.9)),
                lineWidth: 2.0 / pixelScale)
        }
    }

    /// **The headlight cone — the facing cue.** In the car's own color, so it also
    /// helps tell the cars apart; brightest where it leaves the nose, gone by the tip.
    ///
    /// It replaced the two white nose dots: at race zoom they were a couple of pixels,
    /// and reading which end of a smudge carries the dots is not a glance question. A
    /// colored cone the car's own width is.
    ///
    /// The cone arrives already clipped (see `Headlight`): walls the car cannot pass
    /// stop it — a nose shoved into a wall included — a covering deck's edge ends it,
    /// and the road ahead, ramps included, never touches it. The polygon is the near
    /// points out and the tips back, so the stretch inside the car is never painted.
    static func drawHeadlight(
        car: CarState, color: Color, track: Track, scale: Double = 1,
        into context: inout GraphicsContext
    ) {
        let rays = Headlight.rays(car: car, track: track, scale: scale)
        guard rays.contains(where: { $0.near.distance(to: $0.tip) > 0.5 }) else { return }
        // One ring: out along the nose line, back along the tips. A second addLines
        // call would START A NEW SUBPATH — measured on device as no cone at all, the
        // fill reduced to the sliver between the tip arc and its chord.
        let ring =
            rays.map { CGPoint(x: $0.near.x, y: $0.near.y) }
            + rays.reversed().map { CGPoint(x: $0.tip.x, y: $0.tip.y) }
        var path = Path()
        path.addLines(ring)
        path.closeSubpath()
        context.fill(
            path,
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.5), color.opacity(0)]),
                center: CGPoint(x: car.position.x, y: car.position.y),
                startRadius: Headlight.apexDepth * scale,
                endRadius: (Headlight.apexDepth + Headlight.reach) * scale))
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
