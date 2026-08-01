import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// Not a test: a LOOK PROBE. Renders the car drawing to a PNG for visual
/// iteration (`CAR_PROBE_OUT=/path/out.png swift test --filter CarLookProbe`);
/// skips when the output path isn't set, so CI never runs it.
@MainActor
final class CarLookProbe: XCTestCase {
    func testRender() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CAR_PROBE_OUT"] != nil,
            "set CAR_PROBE_OUT to render the probe sheet")
        let colors: [Color] = [.red, .white, .yellow, .cyan]
        let canvas = Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(red: 0.28, green: 0.55, blue: 0.25)))
            for (i, color) in colors.enumerated() {
                var state = CarState(
                    position: Vec2(60 + Double(i) * 90, 50), heading: -.pi / 2)
                state.height = 0
                var big = context
                big.scaleBy(x: 2.2, y: 2.2)
                var small = context
                small.translateBy(x: 0, y: 160)
                small.scaleBy(x: 0.55, y: 0.55)
                TrackRenderer.probeDrawCar(state, color: color, into: &big)
                var tiny = state
                tiny.position = Vec2(110 + Double(i) * 160, 120)
                TrackRenderer.probeDrawCar(tiny, color: color, into: &small)
            }
        }.frame(width: 800, height: 260)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAR_PROBE_OUT"]!)
        guard let cg = renderer.cgImage else { XCTFail("no image"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        print("CLP wrote \(url.path)")
    }
}
