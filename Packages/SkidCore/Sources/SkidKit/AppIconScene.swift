import SkidCore
import SwiftUI

/// The app icon, drawn by the game's own recipe — a red open-wheeler
/// mid-drift through a kerbed corner, rubber arcing behind it. No image
/// assets: `make icon` renders this at 1024×1024 into the asset catalog.
public struct AppIconScene: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let s = size.width / 1024  // designed at 1024

            // Asphalt field.
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(white: 0.4))
            )

            // A kerbed corner sweeping through the bottom-left: grass
            // outside, striped kerb band on the ribbon edge.
            let corner = CGPoint(x: -260 * s, y: 1290 * s)
            func arc(radius: CGFloat) -> Path {
                var path = Path()
                path.addArc(
                    center: corner, radius: radius,
                    startAngle: .degrees(-90), endAngle: .degrees(10), clockwise: false)
                return path
            }
            context.stroke(
                arc(radius: 760 * s), with: .color(Color(red: 0.28, green: 0.55, blue: 0.23)),
                style: StrokeStyle(lineWidth: 560 * s))
            context.stroke(
                arc(radius: 1052 * s), with: .color(Color(white: 0.95)),
                style: StrokeStyle(lineWidth: 66 * s))
            context.stroke(
                arc(radius: 1052 * s), with: .color(Color(red: 0.82, green: 0.16, blue: 0.14)),
                style: StrokeStyle(lineWidth: 66 * s, dash: [110 * s, 110 * s]))

            // The drift: two rubber arcs CURVING WITH THE CORNER —
            // concentric with the kerb, one per rear tire, ending exactly
            // at the swung-out rear axle.
            for offset in [-44.0, 44.0] {
                var trail = Path()
                trail.addArc(
                    center: corner, radius: (1302 + offset) * s,
                    startAngle: .degrees(-8), endAngle: .degrees(-41), clockwise: true)
                context.stroke(
                    trail, with: .color(.black.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 42 * s, lineCap: .round))
            }

            // The car, big and sideways — mid-drift. Same recipe as the
            // in-game car, scaled up.
            // Nose rotated INTO the left-hand corner (past the direction of
            // travel, which the trails show) — the oversteer angle is what
            // makes it read as a drift, not a parked car.
            var car = context
            car.translateBy(x: 620 * s, y: 380 * s)
            car.rotate(by: .degrees(-152))
            car.scaleBy(x: 10.4 * s, y: 10.4 * s)
            for offset in CarGeometry.tireOffsets {
                var tire = car
                tire.translateBy(x: offset.x, y: offset.y)
                if offset.x > 0 {
                    // Front wheels on opposite lock — counter-steering out
                    // of the slide.
                    tire.rotate(by: .degrees(26))
                }
                tire.fill(
                    Path(roundedRect: CGRect(x: -4.5, y: -3, width: 9, height: 6), cornerRadius: 2),
                    with: .color(Color(white: 0.12)))
            }
            let body = CGRect(
                x: -CarGeometry.length / 2, y: -CarGeometry.width / 4,
                width: CarGeometry.length, height: CarGeometry.width / 2)
            car.fill(
                Path(roundedRect: body, cornerRadius: CarGeometry.width / 4),
                with: .color(.red))
            let cockpit = CGRect(x: -4, y: -3.2, width: 6.4, height: 6.4)
            car.fill(Path(ellipseIn: cockpit), with: .color(.black.opacity(0.65)))
        }
    }
}
