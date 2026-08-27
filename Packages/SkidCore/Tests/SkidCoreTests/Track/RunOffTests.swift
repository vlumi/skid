import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **One road width of grass around every compiled track**, and the editor
/// draws that same frame while building. The frame used to hug the outermost
/// kerb, so leaving the road near the edge hit an invisible wall at once.
@MainActor
final class RunOffTests: XCTestCase {
    /// The inset from the world's edge to the centerline at the road's extreme:
    /// the drawn half-road (deck-widened, plus kerb) plus the run-off.
    private var inset: Double {
        Double(PieceCatalog.width) / 2 * Elevation.scale(atHeight: 1)
            + Double(PieceCatalog.kerbBand) + PieceCompiler.runOff
    }

    func testEveryBuiltinHasARoadWidthOfRunOff() throws {
        XCTAssertEqual(PieceCompiler.runOff, Double(PieceCatalog.width))
        for builtin in TrackLibrary.builtins {
            let track = try PieceCompiler.compile(TrackCode.decode(builtin.code), id: builtin.id)
            let xs = track.centerline.map(\.x), ys = track.centerline.map(\.y)
            // The road is centred in its frame, and no chrome overhangs on these,
            // so the extreme centerline sits exactly one inset from each edge.
            XCTAssertGreaterThanOrEqual(xs.min()!, inset - 1e-6, "\(builtin.id) left")
            XCTAssertGreaterThanOrEqual(ys.min()!, inset - 1e-6, "\(builtin.id) top")
            XCTAssertGreaterThanOrEqual(
                track.size.x - xs.max()!, inset - 1e-6, "\(builtin.id) right")
            XCTAssertGreaterThanOrEqual(
                track.size.y - ys.max()!, inset - 1e-6, "\(builtin.id) bottom")
            // And at least one axis is tight to the inset — the frame is not
            // padded beyond what the rule says.
            let slackX = min(xs.min()!, track.size.x - xs.max()!) - inset
            let slackY = min(ys.min()!, track.size.y - ys.max()!) - inset
            XCTAssertLessThan(min(slackX, slackY), 1e-6, "\(builtin.id) over-padded")
        }
    }

    /// **The editor's frame IS the race's world**: same size, for every
    /// builtin — so what an author sees drawn is what will be raced.
    func testTheEditorFrameMatchesTheCompiledWorld() throws {
        for builtin in TrackLibrary.builtins {
            let layout = try TrackCode.decode(builtin.code)
            let track = try PieceCompiler.compile(layout, id: builtin.id)
            let frame = try XCTUnwrap(PieceCompiler.worldFrame(layout))
            XCTAssertEqual(frame.size.x, track.size.x, accuracy: 1e-6, builtin.id)
            XCTAssertEqual(frame.size.y, track.size.y, accuracy: 1e-6, builtin.id)
            // And the shift the compiler applied is exactly the frame's origin.
            XCTAssertEqual(track.layoutOffset.x, -frame.origin.x, accuracy: 1e-6, builtin.id)
            XCTAssertEqual(track.layoutOffset.y, -frame.origin.y, accuracy: 1e-6, builtin.id)
        }
    }

    /// An unfinished loop still has a frame to draw — the editor must never
    /// lose the grass mid-build.
    func testAnUnfinishedLayoutStillHasAFrame() throws {
        var layout = try TrackCode.decode(TrackLibrary.builtins[0].code)
        layout.pieces.removeLast()
        XCTAssertNotNil(PieceCompiler.worldFrame(layout))
    }

    /// **The editor paints the frame as grass**, pixel-sampled: green inside
    /// the frame away from the road, the canvas colour just outside it.
    func testTheEditorDrawsGrassOverTheFrame() throws {
        let layout = try TrackCode.decode(TrackLibrary.builtins[1].code)  // the oval
        let walk = layout.walk()
        let frame = try XCTUnwrap(PieceCompiler.worldFrame(layout))
        let size = CGSize(width: 600, height: 500)
        let t = EditorRenderer.fit(walk: walk, in: size, zoom: 1, pan: .zero)
        let view = Canvas { context, _ in
            EditorRenderer.draw(
                walk: walk, width: Double(PieceCatalog.width), selectedEnd: nil,
                worldFrame: frame, transform: t, into: &context)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        func greenness(_ p: CGPoint) -> Double {
            let o = Int(p.y) * image.bytesPerRow + Int(p.x) * 4
            return (Double(data[o + 1]) - Double(data[o + 2])) / 255
        }
        func screen(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * t.scale + t.offset.width, y: y * t.scale + t.offset.height)
        }
        // A corner of the frame is grass (run-off, no road there)…
        let corner = screen(frame.origin.x + 4, frame.origin.y + 4)
        XCTAssertGreaterThan(greenness(corner), 0.15, "no grass inside the frame")
        // …and just outside it is not.
        let outside = screen(frame.origin.x - 6, frame.origin.y - 6)
        XCTAssertLessThanOrEqual(greenness(outside), 0.05, "grass outside the frame")
    }
}
