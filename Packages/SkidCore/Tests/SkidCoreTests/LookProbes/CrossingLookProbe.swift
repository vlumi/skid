import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// Not a test: a LOOK PROBE for an at-grade crossing. Flattens the eight
/// built-in (all pitches removed), so its bridge crossing becomes two roads
/// sharing tarmac at height 0, and renders the editor's view of it —
/// answering "do the edge lines get interrupted through the intersection by
/// the existing paint order alone?"
@MainActor
final class CrossingLookProbe: XCTestCase {
    func testRender() throws {
        guard let out = ProcessInfo.processInfo.environment["CROSSING_PROBE_OUT"] else {
            throw XCTSkip("set CROSSING_PROBE_OUT to render the probe sheet")
        }
        let eight = try TrackCode.decode(
            try XCTUnwrap(TrackLibrary.builtins.first { $0.id == "eight" }).code)
        var flat = eight
        flat.pitches = []
        flat.originHeight = 0
        let walk = flat.walk()
        XCTAssertNil(walk.failure)

        // Fit the layout into the canvas.
        var xs: [Double] = []
        var ys: [Double] = []
        for p in walk.placed {
            for v in p.centerlineSamples(degreesPerSample: 10) {
                xs.append(v.x)
                ys.append(v.y)
            }
        }
        let minX = xs.min()! - 90
        let minY = ys.min()! - 90
        let spanX = xs.max()! + 90 - minX
        let spanY = ys.max()! + 90 - minY
        let size = CGSize(width: 900, height: 900 * spanY / spanX)
        let scale = size.width / spanX

        let canvas = Canvas { context, canvasSize in
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(Color(red: 0.28, green: 0.55, blue: 0.25)))
            let transform = EditorRenderer.Transform(
                scale: scale,
                offset: CGSize(width: -minX * scale, height: -minY * scale))
            EditorRenderer.drawTrack(
                walk: walk, width: Double(PieceCatalog.width), gateSeams: [],
                transform: transform, into: &context)
        }.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            XCTFail("no image")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        try rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
            .write(to: URL(fileURLWithPath: out))
        print("CLP wrote \(out)")
    }
}
