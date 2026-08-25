import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **What the zoned pad actually paints** — pixel-sampled, because under
/// follow-movement steering the thumb's position says nothing about the lock:
/// if the wheel bar is not really drawn, the held steer is invisible, which is
/// the founding bug of this whole control rework. A model test cannot see it.
@MainActor
final class PadOverlayRenderTests: XCTestCase {
    /// A zone with its strip edge at y = 60, so the bar's row is known.
    private let zone = CGRect(x: 0, y: 0, width: 187, height: 200)

    private func render(steer: Double) throws -> CGImage {
        let pad = DPadOverlay(
            origin: Vec2(93.5, 100), up: Vec2(0, -1), radius: 48,
            zone: zone, cruiseStrip: 0.3, brakeBand: 0.25,
            knob: .zero,
            input: CarInput(steer: steer, throttle: 1),
            color: Color(red: 1, green: 0, blue: 0),
            engaged: true)
        let view = Canvas { context, _ in
            OverlayRenderer.drawDPad(pad, into: &context)
        }
        .frame(width: zone.width, height: zone.height)
        .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: zone.width, height: zone.height)
        // 4x, so a sample can sit inside the 5-point bar yet clear of the
        // 2-point edge line that shares its row.
        renderer.scale = 4
        return try XCTUnwrap(renderer.cgImage)
    }

    /// Red channel 0…1 at a point in VIEW coordinates.
    private func red(_ image: CGImage, x: Double, y: Double) throws -> Double {
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        let px = Int(x * 4), py = Int(y * 4)
        let offset = py * image.bytesPerRow + px * 4
        return Double(data[offset]) / 255
    }

    /// **A held lock is drawn as a bar along the strip edge**, from the zone's
    /// middle toward the steered side — and only on that side.
    func testTheWheelBarIsDrawnOnTheSteeredSide() throws {
        let image = try render(steer: 0.8)
        // y 61.75: inside the bar (edge ± 2.5) but clear of the edge line
        // (edge ± 1). x 130 is inside a 0.8 lock's reach (93.5…168).
        let inBar = try red(image, x: 130, y: 61.75)
        XCTAssertGreaterThan(inBar, 0.5, "the wheel bar is not drawn (red \(inBar))")
        // The unsteered side of the same row: nothing but background.
        let offSide = try red(image, x: 57, y: 61.75)
        XCTAssertLessThan(offSide, 0.2, "a bar appeared on the unsteered side")
    }

    /// **Straight ahead draws no bar** — a bar that never disappears would
    /// read as a lock that is not there.
    func testNoBarWhenStraight() throws {
        let image = try render(steer: 0)
        let sample = try red(image, x: 130, y: 61.75)
        XCTAssertLessThan(sample, 0.2, "a bar is drawn with no steer (red \(sample))")
    }
}
