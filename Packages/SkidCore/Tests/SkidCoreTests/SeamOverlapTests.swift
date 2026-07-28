import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// Hairline gaps at piece seams. The geometry is exact — abutting pieces share
/// their seam to the unit — so any visible gap is an antialiasing artifact,
/// and the cure is an overlap wide enough to cover the blend.
final class SeamOverlapTests: XCTestCase {
    /// Adjacent pieces meet EXACTLY: whatever shows on a device is the
    /// renderer's antialiasing, not a hole in the model. Worth pinning, since
    /// a real geometric gap would need a completely different fix.
    func testAdjacentPiecesMeetExactly() throws {
        for id in ["small", "oval", "eight", "clover"] {
            let layout = try XCTUnwrap(TrackLibrary.layout(id: id))
            let placed = layout.walk().placed
            for index in 0..<(placed.count - 1) {
                let gap = placed[index].exits[0].position.vec2
                    .distance(to: placed[index + 1].entry.position.vec2)
                XCTAssertEqual(gap, 0, accuracy: 1e-9, "\(id): seam \(index) is not exact")
            }
        }
    }

    /// The overlap must clear an antialiased edge, not just one device pixel:
    /// 0.33pt at 3×, 0.5pt at 2×, but the blend spreads about a point either
    /// side of a diagonal seam. It is in SCREEN points, so zooming out can't
    /// shrink it below that.
    func testTheOverlapClearsAnAntialiasedEdge() {
        XCTAssertGreaterThanOrEqual(
            EditorRenderer.seamOverlap, 1,
            "an overlap under a point leaves hairlines on a 3x screen")
    }
}
