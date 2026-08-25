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
        drawSpeed(zone, in: rect, into: &context)
    }

    /// **Each player's own speedometer**, in the corner of their control box.
    ///
    /// A digital read-out rather than a dial: at this size a needle would be a
    /// few pixels of sweep, and the number is what a player actually wants ("am
    /// I near the limit", "am I in reverse"). Signed, so reversing shows a
    /// negative — `velocity.length` cannot distinguish the two, and not noticing
    /// you are in reverse is a reported confusion.
    ///
    /// Placed at the corner FURTHEST from the map, and rotated with the zone, so
    /// it reads upright for a player sitting across the table and never sits
    /// under the thumb that rests mid-box.
    private static func drawSpeed(
        _ zone: ZoneChrome, in rect: CGRect, into context: inout GraphicsContext
    ) {
        guard let speed = zone.speed else { return }
        let text = context.resolve(
            Text(verbatim: speed)
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundColor(zone.color.opacity(0.9)))
        let size = text.measure(in: rect.size)
        // The home edge is opposite `up`; the readout goes to its outer corner,
        // inset clear of the box's own stroke.
        let inset = 8.0
        let awayFromMap = zone.up * -1
        var center = Vec2(rect.midX, rect.midY)
        if awayFromMap.y != 0 {
            center.y += awayFromMap.y * (rect.height / 2 - size.height / 2 - inset)
            center.x = rect.minX + size.width / 2 + inset
        } else {
            center.x += awayFromMap.x * (rect.width / 2 - size.width / 2 - inset)
            center.y = rect.minY + size.height / 2 + inset
        }
        // Rotated for a player across the table, exactly as their pad is.
        if zone.up.y > 0 {
            var flipped = context
            flipped.translateBy(x: center.x, y: center.y)
            flipped.rotate(by: .degrees(180))
            flipped.draw(text, at: .zero, anchor: .center)
        } else {
            context.draw(text, at: CGPoint(x: center.x, y: center.y), anchor: .center)
        }
    }

    /// The floating d-pad: a faint disc plus four arrows in the owning
    /// player's color, arrows lighting up with per-axis engagement. Drawn
    /// in screen coordinates, over the world. **Always visible** — resting
    /// dimmed where the thumb left it (or at the zone center before any
    /// touch), so a new player sees where to press before pressing.
    static func drawDPad(_ pad: DPadOverlay, into context: inout GraphicsContext) {
        let rest = pad.engaged ? 1.0 : 0.55
        // **The zone model draws its regions, not a floating disc.** The whole
        // point is an edge the thumb can find, so the edge has to be visible
        // while it is being learned.
        if let zone = pad.zone {
            drawZonedPad(pad, zone: zone, rest: rest, into: &context)
            return
        }
        let disc = CGRect(
            x: pad.origin.x - pad.radius, y: pad.origin.y - pad.radius,
            width: pad.radius * 2, height: pad.radius * 2
        )
        context.fill(Path(ellipseIn: disc), with: .color(pad.color.opacity(0.12 * rest)))

        // **A visible straight-ahead**, and the thumb's offset from it.
        //
        // The pad was a 12%-opacity disc with nothing marking its middle, so
        // after a corner there was no way to see where centre had ended up —
        // you held a small steer you could not detect and sailed down the lane
        // in a slow sine curve. Reported exactly that way. The crosshair says
        // where straight is; the line to the knob says how far off it you are,
        // which is the reading a thumb cannot take by feel on glass.
        let tick = 7.0
        var cross = Path()
        cross.move(to: CGPoint(x: pad.origin.x - tick, y: pad.origin.y))
        cross.addLine(to: CGPoint(x: pad.origin.x + tick, y: pad.origin.y))
        cross.move(to: CGPoint(x: pad.origin.x, y: pad.origin.y - tick))
        cross.addLine(to: CGPoint(x: pad.origin.x, y: pad.origin.y + tick))
        context.stroke(cross, with: .color(pad.color.opacity(0.9 * rest)), lineWidth: 2)

        // The steer offset only: a horizontal bar from centre to where the
        // thumb sits across the pad. Vertical offset is throttle, which the
        // arrows already report and which nobody has to null out.
        let across = pad.up.perpendicular
        let sideways = pad.knob.dot(across)
        if abs(sideways) > 1 {
            let end = pad.origin + across * sideways
            var bar = Path()
            bar.move(to: CGPoint(x: pad.origin.x, y: pad.origin.y))
            bar.addLine(to: CGPoint(x: end.x, y: end.y))
            context.stroke(
                bar, with: .color(pad.color.opacity(0.85 * rest)), lineWidth: 3)
            let dot = CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dot), with: .color(pad.color.opacity(0.95 * rest)))
        }

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

    /// The strip model: a bright cruise band at the top (full throttle, no
    /// steering, slide to reposition), the driving band below it, and a brake
    /// band at the bottom. The lower edge of the strip is the thing a thumb
    /// learns by feel, so it is drawn as a real line.
    private static func drawZonedPad(
        _ pad: DPadOverlay, zone: CGRect, rest: Double, into context: inout GraphicsContext
    ) {
        // `up` points away from the player, so a flipped seat's gas end is
        // the bottom of the screen rect.
        let flipped = pad.up.y > 0

        // **The throttle axis, painted.** The player's color, strongest where
        // the gas (and, past the transparent coast point, the reverse) is
        // strongest — the zone itself is the legend, and the uncolored gap IS
        // neutral. No band edges to find: the mapping is continuous and so is
        // the paint.
        let coastY =
            flipped
            ? zone.maxY - pad.coastDepth * zone.height
            : zone.minY + pad.coastDepth * zone.height
        let gasEnd = flipped ? zone.maxY : zone.minY
        let reverseEnd = flipped ? zone.minY : zone.maxY
        let gas = Gradient(colors: [pad.color.opacity(0.28 * rest), pad.color.opacity(0)])
        context.fill(
            Path(
                CGRect(
                    x: zone.minX, y: min(gasEnd, coastY), width: zone.width,
                    height: abs(coastY - gasEnd))),
            with: .linearGradient(
                gas, startPoint: CGPoint(x: zone.midX, y: gasEnd),
                endPoint: CGPoint(x: zone.midX, y: coastY)))
        let reverse = Gradient(colors: [pad.color.opacity(0), pad.color.opacity(0.20 * rest)])
        context.fill(
            Path(
                CGRect(
                    x: zone.minX, y: min(coastY, reverseEnd), width: zone.width,
                    height: abs(reverseEnd - coastY))),
            with: .linearGradient(
                reverse, startPoint: CGPoint(x: zone.midX, y: coastY),
                endPoint: CGPoint(x: zone.midX, y: reverseEnd)))

        // **The steering, as a full-height line.** The old ring implied a
        // two-axis stick, which was a lie — only the sideways gap steers.
        // The line is the neutral column: it slides with the wheel, the
        // thumb's distance from it is the live steer, faint rails a travel
        // away are full lock, and a still thumb watches the line come back
        // underneath it as the wheel recentres.
        if pad.engaged, let base = pad.stickBase, let thumb = pad.thumb {
            func vertical(at x: Double, width: Double, opacity: Double) {
                var line = Path()
                line.move(to: CGPoint(x: x, y: zone.minY))
                line.addLine(to: CGPoint(x: x, y: zone.maxY))
                context.stroke(
                    line, with: .color(pad.color.opacity(opacity)), lineWidth: width)
            }
            vertical(at: base.x, width: 2, opacity: 0.9)
            vertical(at: base.x - pad.stickRadius, width: 1, opacity: 0.3)
            vertical(at: base.x + pad.stickRadius, width: 1, opacity: 0.3)
            // The gap itself — the live steer reading, at the thumb.
            var bar = Path()
            bar.move(to: CGPoint(x: base.x, y: thumb.y))
            bar.addLine(to: CGPoint(x: thumb.x, y: thumb.y))
            context.stroke(bar, with: .color(pad.color.opacity(0.9)), lineWidth: 4)
            let dot = CGRect(x: thumb.x - 7, y: thumb.y - 7, width: 14, height: 14)
            context.fill(Path(ellipseIn: dot), with: .color(pad.color.opacity(0.95)))
        }
    }

    /// The countdown's "this one is yours": a small halo of the player's color
    /// worn ON their car, tethered by a thin leader line to their control band.
    /// The halo is smaller than the car, so overlaying it hides nothing — and it
    /// shows through anywhere the car itself shows, the under-deck window
    /// bubbles included. The line runs unbroken to the halo's rim: at 2 points
    /// and half opacity it may graze a neighbouring car, which was judged better
    /// than a gap — and being one overlay stroke it neither dives under bridges
    /// nor gaps at a deck's edge (both were built and reverted; see history).
    static func drawGridMarkers(_ markers: [GridMarker], into context: inout GraphicsContext) {
        let radius = 7.0
        for marker in markers {
            let toCar = marker.position - marker.leaderStart
            if toCar.length > radius + 1 {
                let end = marker.position - toCar.normalized * radius
                var line = Path()
                line.move(to: CGPoint(x: marker.leaderStart.x, y: marker.leaderStart.y))
                line.addLine(to: CGPoint(x: end.x, y: end.y))
                context.stroke(line, with: .color(marker.color.opacity(0.55)), lineWidth: 2)
            }
            let disc = CGRect(
                x: marker.position.x - radius, y: marker.position.y - radius,
                width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: disc), with: .color(marker.color.opacity(0.3)))
            context.stroke(
                Path(ellipseIn: disc), with: .color(marker.color.opacity(0.9)), lineWidth: 2)
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

}
