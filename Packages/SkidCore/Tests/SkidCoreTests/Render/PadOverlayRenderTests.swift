import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **What the zoned pad actually paints** — pixel-sampled, because the whole
/// point of the joystick visual is that the held lock is VISIBLE: steer is the
/// gap between the thumb and the base, and if either is not really drawn the
/// lock is invisible again, which is the founding bug of this control rework.
/// A model test cannot see a missing stroke.
@MainActor
final class PadOverlayRenderTests: XCTestCase {
    private let zone = CGRect(x: 0, y: 0, width: 187, height: 200)

    private func render(base: Vec2, thumb: Vec2) throws -> CGImage {
        let pad = DPadOverlay(
            origin: Vec2(93.5, 100), up: Vec2(0, -1), radius: 48,
            zone: zone, cruiseStrip: 0.3, brakeBand: 0.25,
            knob: .zero,
            stickBase: base, thumb: thumb, stickRadius: 60,
            input: CarInput(steer: 0, throttle: 1),
            color: Color(red: 1, green: 0, blue: 0),
            engaged: true)
        let view = Canvas { context, _ in
            OverlayRenderer.drawDPad(pad, into: &context)
        }
        .frame(width: zone.width, height: zone.height)
        .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: zone.width, height: zone.height)
        renderer.scale = 4
        return try XCTUnwrap(renderer.cgImage)
    }

    /// Red channel 0…1 at a point in VIEW coordinates.
    private func red(_ image: CGImage, x: Double, y: Double) throws -> Double {
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        let offset = Int(y * 4) * image.bytesPerRow + Int(x * 4) * 4
        return Double(data[offset]) / 255
    }

    /// **The gap between base and thumb is drawn**, and the ring's rim sits a
    /// travel from the base — the rim IS full lock, so it must be where the
    /// numbers say.
    func testTheStickAndItsGapAreDrawn() throws {
        let image = try render(base: Vec2(60, 100), thumb: Vec2(110, 100))
        // Mid-gap: the steer bar.
        let gap = try red(image, x: 85, y: 100)
        XCTAssertGreaterThan(gap, 0.5, "the steer gap is not drawn (red \(gap))")
        // The rim, straight below the base: stroke at radius 60.
        let rim = try red(image, x: 60, y: 160)
        XCTAssertGreaterThan(rim, 0.3, "the rim is not drawn (red \(rim))")
        // Same row as the gap but past the thumb: background only.
        let off = try red(image, x: 150, y: 100)
        XCTAssertLessThan(off, 0.2, "paint where neither bar nor ring should be")
    }

    /// **Centred means no gap**: base under the thumb draws no bar, so a bar
    /// that never disappears cannot lie about a lock that is not there.
    func testNoGapWhenTheBaseIsUnderTheThumb() throws {
        let image = try render(base: Vec2(110, 100), thumb: Vec2(110, 100))
        let sample = try red(image, x: 85, y: 100)
        XCTAssertLessThan(sample, 0.2, "a gap is drawn while centred (red \(sample))")
    }
}
