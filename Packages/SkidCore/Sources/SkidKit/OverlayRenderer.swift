import SkidCore
import SwiftUI

/// Screen-space chrome drawn over the world: control-zone outlines and the
/// floating d-pads.
enum OverlayRenderer {
    /// A player's zone chrome on a shared screen: a soft fill of the
    /// player's colour so whose-is-whose reads at a glance over the grass,
    /// a stronger outline, plus a tab on the player's own edge (where their
    /// `up` points from).
    static func drawZone(_ zone: ZoneChrome, into context: inout GraphicsContext) {
        let rect = zone.rect.insetBy(dx: 3, dy: 3)
        let shape = Path(roundedRect: rect, cornerRadius: 10)
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
        context.fill(
            Path(roundedRect: tab, cornerRadius: 5), with: .color(zone.color.opacity(0.6)))
    }

    /// The floating d-pad: a faint disc plus four arrows in the owning
    /// player's color, arrows lighting up with per-axis engagement. Drawn
    /// in screen coordinates, over the world.
    static func drawDPad(_ pad: DPadOverlay, into context: inout GraphicsContext) {
        let disc = CGRect(
            x: pad.origin.x - pad.radius, y: pad.origin.y - pad.radius,
            width: pad.radius * 2, height: pad.radius * 2
        )
        context.fill(Path(ellipseIn: disc), with: .color(pad.color.opacity(0.12)))

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
            context.fill(path, with: .color(pad.color.opacity(0.35 + 0.6 * engagement)))
        }
    }

    /// The floating aim stick: a faint disc plus a single pointer from the
    /// origin toward the aimed direction, in the owning player's color —
    /// where you point is where the car heads.
    static func drawAim(_ aim: AimOverlay, into context: inout GraphicsContext) {
        let disc = CGRect(
            x: aim.origin.x - aim.radius, y: aim.origin.y - aim.radius,
            width: aim.radius * 2, height: aim.radius * 2
        )
        context.fill(Path(ellipseIn: disc), with: .color(aim.color.opacity(0.12)))
        guard aim.knob.length > 1 else { return }
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
}
