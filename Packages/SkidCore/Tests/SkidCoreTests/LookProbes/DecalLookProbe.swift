import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// Not a test: a LOOK PROBE for the direction-arrow decal. Paints one on EVERY
/// piece of the clover — straights, all three corner radii, and ramps — so the
/// question "does the arrow follow the curve, and does it read at a glance?" is
/// answered by looking rather than by asserting.
@MainActor
final class DecalLookProbe: XCTestCase {
    func testRender() throws {
        guard let out = ProcessInfo.processInfo.environment["DECAL_PROBE_OUT"] else {
            throw XCTSkip("set DECAL_PROBE_OUT to render the probe sheet")
        }
        // Default: the clover with an arrow on EVERY piece, so all the shapes show
        // at once. Override with DECAL_PROBE_CODE to look at a specific track.
        var layout: TrackLayout
        if let code = ProcessInfo.processInfo.environment["DECAL_PROBE_CODE"] {
            layout = try TrackCode.decode(code)
        } else {
            layout = try TrackCode.decode(
                try XCTUnwrap(TrackLibrary.builtins.first { $0.id == "clover" }).code)
            for index in layout.pieces.indices { layout.decals[index] = .directionArrow }
        }
        let walk = layout.walk()
        XCTAssertNil(walk.failure)

        var xs: [Double] = []
        var ys: [Double] = []
        for placed in walk.placed {
            for point in placed.centerlineSamples(degreesPerSample: 10) {
                xs.append(point.x)
                ys.append(point.y)
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
                decals: layout.decals, transform: transform, into: &context)
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
        print("DLP wrote \(out)")
    }
}
