import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// Not a test: a LOOK PROBE for the under-deck window. Renders a fake deck
/// with marks and a windowed car (`WINDOW_PROBE_OUT=/path.png swift test
/// --filter WindowLookProbe`); skips when the output path isn't set.
@MainActor
final class WindowLookProbe: XCTestCase {
    func testRender() throws {
        guard let out = ProcessInfo.processInfo.environment["WINDOW_PROBE_OUT"] else {
            throw XCTSkip("set WINDOW_PROBE_OUT to render the probe sheet")
        }
        let canvas = Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(red: 0.28, green: 0.55, blue: 0.25)))
            var world = context
            world.scaleBy(x: 2.4, y: 2.4)
            // A deck strip with a centerline dash and some skid marks on it.
            world.fill(
                Path(CGRect(x: 20, y: 30, width: 280, height: 50)),
                with: .color(Color(white: 0.62)))
            var dash = Path()
            dash.move(to: CGPoint(x: 20, y: 55))
            dash.addLine(to: CGPoint(x: 300, y: 55))
            world.stroke(
                dash, with: .color(.white.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
            for (i, color) in [(60, Color.red), (160, Color.white), (250, Color.cyan)]
                .enumerated().map({ ($0.element.0, $0.element.1) })
            {
                var state = CarState(
                    position: Vec2(Double(i), 55),
                    heading: [0.4, -.pi / 2, 2.6][
                        [60, 160, 250].firstIndex(of: i)!])
                state.height = 0
                TrackRenderer.probeDrawWindow(around: state, color: color, into: &world)
            }
        }.frame(width: 800, height: 260)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { XCTFail("no image"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
            .write(to: URL(fileURLWithPath: out))
        print("WLP wrote \(out)")
    }
}
