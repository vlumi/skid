import SkidCore
import SwiftUI

/// Screen-space chrome drawn over the world: control-zone outlines and the
/// floating d-pads.
enum OverlayRenderer {
    /// A player's zone chrome on a shared screen: a soft fill of the
    /// player's color so whose-is-whose reads at a glance over the grass,
    /// a stronger outline, plus a tab on the player's own edge (where their
    /// `up` points from).
    static func drawZone(_ zone: ZoneChrome, into context: inout GraphicsContext) {
        let rect = zone.rect.insetBy(dx: 3, dy: 3)
        // Square, like everything else now — a rounded card around a pixel-art game
        // was the last piece of native-looking chrome on the race screen.
        let shape = Path(rect)
        context.fill(shape, with: .color(zone.color.opacity(0.15)))
        context.stroke(shape, with: .color(zone.color.opacity(0.5)), lineWidth: 2)
        // Tab at the middle of the zone's "home" edge (opposite of up),
        // pulled inside the safe area so it never hides under the notch /
        // Dynamic Island (top) or the home indicator (bottom).
        let center = Vec2(rect.midX, rect.midY)
        let halfSpan = zone.up.y != 0 ? rect.height / 2 : rect.width / 2
        var edge = center - zone.up * (halfSpan - 8)
        edge.y = min(
            max(edge.y, zone.safeInsets.top + 10),
            zone.rect.maxY - zone.safeInsets.bottom - 10)
        let tab = CGRect(x: edge.x - 22, y: edge.y - 5, width: 44, height: 10)
        context.fill(Path(tab), with: .color(zone.color.opacity(0.6)))
    }

    /// The floating d-pad: a faint disc plus four arrows in the owning
    /// player's color, arrows lighting up with per-axis engagement. Drawn
    /// in screen coordinates, over the world. **Always visible** — resting
    /// dimmed where the thumb left it (or at the zone center before any
    /// touch), so a new player sees where to press before pressing.
    static func drawDPad(_ pad: DPadOverlay, into context: inout GraphicsContext) {
        let rest = pad.engaged ? 1.0 : 0.55
        let disc = CGRect(
            x: pad.origin.x - pad.radius, y: pad.origin.y - pad.radius,
            width: pad.radius * 2, height: pad.radius * 2
        )
        context.fill(Path(ellipseIn: disc), with: .color(pad.color.opacity(0.12 * rest)))

        let arrows: [(Vec2, Double)] = [
            (pad.up, max(0, pad.input.throttle)),
            (pad.up * -1, max(0, -pad.input.throttle)),
            (pad.up.perpendicular, max(0, pad.input.steer)),
            (pad.up.perpendicular * -1, max(0, -pad.input.steer)),
        ]
        for (direction, engagement) in arrows {
            let tip = pad.origin + direction * (pad.radius + 16)
            let base = pad.origin + direction * (pad.radius - 14)
            let side = direction.perpendicular * 14
            var path = Path()
            path.move(to: CGPoint(x: tip.x, y: tip.y))
            path.addLine(to: CGPoint(x: base.x + side.x, y: base.y + side.y))
            path.addLine(to: CGPoint(x: base.x - side.x, y: base.y - side.y))
            path.closeSubpath()
            context.fill(
                path, with: .color(pad.color.opacity((0.35 + 0.6 * engagement) * rest)))
        }
    }

    /// The floating aim stick: a faint disc plus a single pointer from the
    /// origin toward the aimed direction, in the owning player's color —
    /// where you point is where the car heads. **Always visible** — at rest
    /// (no pointer to draw) the disc gets a rim and a center dot, because the
    /// bare 0.12-opacity disc all but vanishes on grass and the whole point
    /// of a resting stick is being seen before it is touched.
    static func drawAim(_ aim: AimOverlay, into context: inout GraphicsContext) {
        let rest = aim.engaged ? 1.0 : 0.55
        let disc = CGRect(
            x: aim.origin.x - aim.radius, y: aim.origin.y - aim.radius,
            width: aim.radius * 2, height: aim.radius * 2
        )
        context.fill(Path(ellipseIn: disc), with: .color(aim.color.opacity(0.12 * rest)))
        guard aim.knob.length > 1 else {
            context.stroke(
                Path(ellipseIn: disc), with: .color(aim.color.opacity(0.4 * rest)),
                lineWidth: 2)
            let dot = CGRect(
                x: aim.origin.x - 9, y: aim.origin.y - 9, width: 18, height: 18)
            context.fill(Path(ellipseIn: dot), with: .color(aim.color.opacity(0.5 * rest)))
            return
        }
        let direction = aim.knob.normalized
        let tip = aim.origin + direction * (aim.radius + 18)
        let base = aim.origin + direction * (aim.radius - 10)
        let side = direction.perpendicular * 13
        // A shaft toward the aim, capped with an arrowhead.
        context.stroke(
            Path {
                $0.move(to: CGPoint(x: aim.origin.x, y: aim.origin.y))
                $0.addLine(to: CGPoint(x: base.x, y: base.y))
            },
            with: .color(aim.color.opacity(0.7)), lineWidth: 5)
        var head = Path()
        head.move(to: CGPoint(x: tip.x, y: tip.y))
        head.addLine(to: CGPoint(x: base.x + side.x, y: base.y + side.y))
        head.addLine(to: CGPoint(x: base.x - side.x, y: base.y - side.y))
        head.closeSubpath()
        context.fill(head, with: .color(aim.color.opacity(0.9)))
    }

    /// The countdown's "this one is yours": a square ring around the player's
    /// car and a numbered chip on their side of it, the number rotated to face
    /// them. Square, like every other marker in the game. The chip is dark with
    /// a colored rim and a white number — white-on-dark stays readable whatever
    /// the player's color, and the ring already shouts the color itself.
    static func drawGridMarker(_ marker: GridMarker, into context: inout GraphicsContext) {
        let radius: CGFloat = 22
        let ring = CGRect(
            x: marker.position.x - radius, y: marker.position.y - radius,
            width: radius * 2, height: radius * 2)
        context.stroke(Path(ring), with: .color(marker.color.opacity(0.9)), lineWidth: 3)

        // The chip sits on the player's side of the ring (their edge is where
        // `up` points FROM), rotated so its top is the player's up.
        let center = marker.position - marker.up * (Double(radius) + 20)
        var chip = context
        chip.translateBy(x: center.x, y: center.y)
        chip.rotate(by: Angle(radians: atan2(marker.up.x, -marker.up.y)))
        let box = CGRect(x: -13, y: -13, width: 26, height: 26)
        chip.fill(Path(box), with: .color(.black.opacity(0.7)))
        chip.stroke(Path(box), with: .color(marker.color.opacity(0.9)), lineWidth: 2)
        chip.draw(
            Text(verbatim: "\(marker.number)")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(.white),
            at: .zero)
    }
}
