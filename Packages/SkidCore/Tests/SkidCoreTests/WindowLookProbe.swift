import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// Not a test: a LOOK PROBE for the under-deck window. Renders a fake deck
/// with rails and windowed cars (`WINDOW_PROBE_OUT=/path.png swift test
/// --filter WindowLookProbe`); skips when the output path isn't set.
///
/// Cases on the sheet: mid-deck, mid-deck with a deck car passing OVER the
/// hole, and a car under the deck EDGE (the hole must stop at the asphalt and
/// leave the rail solid).
@MainActor
final class WindowLookProbe: XCTestCase {
    private struct Probe {
        let at: Vec2
        let heading: Double
        let color: Color
    }

    func testRender() throws {
        guard let out = ProcessInfo.processInfo.environment["WINDOW_PROBE_OUT"] else {
            throw XCTSkip("set WINDOW_PROBE_OUT to render the probe sheet")
        }
        let canvas = Canvas { context, size in
            Self.drawSheet(into: context, size: size)
        }.frame(width: 800, height: 260)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            XCTFail("no image")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        try rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
            .write(to: URL(fileURLWithPath: out))
        print("WLP wrote \(out)")
    }

    private static func drawSheet(into context: GraphicsContext, size: CGSize) {
        do {
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(red: 0.28, green: 0.55, blue: 0.25)))
            var world = context
            world.scaleBy(x: 2.4, y: 2.4)
            let deck = Path(CGRect(x: 20, y: 30, width: 280, height: 50))
            world.fill(deck, with: .color(Color(white: 0.62)))
            var dash = Path()
            dash.move(to: CGPoint(x: 20, y: 55))
            dash.addLine(to: CGPoint(x: 300, y: 55))
            world.stroke(
                dash, with: .color(.white.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))

            let cases: [Probe] = [
                Probe(at: Vec2(60, 55), heading: 0.4, color: .red),  // mid-deck
                // Mid-deck; the yellow deck car passes over this one's hole.
                Probe(at: Vec2(160, 55), heading: -.pi / 2, color: .white),
                // Under the deck EDGE: sliver only, rail stays solid.
                Probe(at: Vec2(250, 76), heading: 2.6, color: .cyan),
            ]
            for c in cases {
                var state = CarState(position: c.at, heading: c.heading)
                state.height = 0
                TrackRenderer.probeDrawWindow(
                    around: state, color: c.color, deck: deck, into: &world)
            }
            // A real car ON the deck, drawn after the windows (higher kind):
            // it must pass over the white car's hole, not under its ghost.
            var deckCar = CarState(position: Vec2(172, 50), heading: 0.2)
            deckCar.height = 1
            TrackRenderer.probeDrawCar(deckCar, color: .yellow, into: &world)

            // The rails paint over everything of the deck's road layer in the
            // real renderer; here just drawn last to eyeball the hole edge.
            for railY in [30.0, 80.0] {
                var rail = Path()
                rail.move(to: CGPoint(x: 20, y: railY))
                rail.addLine(to: CGPoint(x: 300, y: railY))
                world.stroke(
                    rail, with: .color(Color(red: 0.55, green: 0.75, blue: 0.95)),
                    lineWidth: 4)
            }
        }
    }
}
