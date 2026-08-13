import Foundation
import XCTest

@testable import SkidCore
@testable import SkidKit

@MainActor
final class FitCheckTests: XCTestCase {
    /// The old inline maths, verbatim from git history, against the shared helper.
    func testSharedFitMatchesTheOldInlineMaths() throws {
        for id in ["small", "oval", "eight", "clover"] {
            let walk = try XCTUnwrap(TrackLibrary.layout(id: id)).walk()
            for view in [CGSize(width: 390, height: 700), CGSize(width: 750, height: 1200)] {
                for zoom in [CGFloat(1), 1.5, 0.8] {
                    let pan = CGSize(width: 13, height: -7)
                    // OLD
                    let pts = walk.placed.flatMap { placed in
                        placed.piece.paths.indices.flatMap { placed.centerlineSamples(path: $0) }
                    }
                    let half = Double(PieceCatalog.width) / 2
                    let xs = pts.map(\.x), ys = pts.map(\.y)
                    let minX = (xs.min() ?? 0) - half, maxX = (xs.max() ?? 100) + half
                    let minY = (ys.min() ?? 0) - half, maxY = (ys.max() ?? 100) + half
                    let w = max(1, maxX - minX), h = max(1, maxY - minY)
                    let margin: CGFloat = 40
                    let box = CGSize(
                        width: max(1, view.width - 2 * margin),
                        height: max(1, view.height - 2 * margin))
                    let scale = min(box.width / w, box.height / h) * zoom
                    let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
                    let offset = CGSize(
                        width: view.width / 2 - cx * scale + pan.width,
                        height: view.height / 2 - cy * scale + pan.height)
                    // NEW
                    let fit = EditorRenderer.fit(walk: walk, in: view, zoom: zoom, pan: pan)
                    XCTAssertEqual(fit.scale, scale, accuracy: 1e-9, "\(id) scale")
                    XCTAssertEqual(fit.offset.width, offset.width, accuracy: 1e-9, "\(id) dx")
                    XCTAssertEqual(fit.offset.height, offset.height, accuracy: 1e-9, "\(id) dy")
                }
            }
        }
    }
}
