import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **What the Pro pad actually paints** — pixel-sampled, because the whole
/// point of this overlay is that the invisible state is VISIBLE: the throttle
/// axis as a gradient with a transparent coast point, and the held lock as
/// the gap between the thumb and the neutral line. A model test cannot see a
/// missing stroke or a gradient painted the wrong way up.
@MainActor
final class PadOverlayRenderTests: XCTestCase {
    private let zone = CGRect(x: 0, y: 0, width: 187, height: 200)

    private func render(base: Vec2?, thumb: Vec2?, engaged: Bool = true) throws -> CGImage {
        let pad = DPadOverlay(
            origin: Vec2(93.5, 100), up: Vec2(0, -1), radius: 48,
            zone: zone, fullThrottleDepth: 0.3, coastDepth: 0.6,
            knob: .zero,
            stickBase: base, thumb: thumb, stickRadius: 60,
            input: CarInput(steer: 0, throttle: 1),
            color: Color(red: 1, green: 0, blue: 0),
            engaged: engaged)
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

    /// **The throttle gradient runs the right way up**: strongest at the top
    /// (full gas), transparent at the coast point (60% down = y 120), and
    /// building again toward full reverse at the bottom.
    func testTheGasAxisGradient() throws {
        let image = try render(base: nil, thumb: nil, engaged: false)
        let top = try red(image, x: 30, y: 4)
        // Inside the plateau (30% of 200 = y 60): as strong as the very top,
        // because it IS the same throttle.
        let plateau = try red(image, x: 30, y: 50)
        XCTAssertEqual(plateau, top, accuracy: 0.03, "the plateau does not paint flat")
        let coast = try red(image, x: 30, y: 120)
        let bottom = try red(image, x: 30, y: 197)
        // A resting pad draws dimmed, so the absolute floor is modest; the
        // comparative asserts below carry the direction claim.
        XCTAssertGreaterThan(top, 0.1, "no gas colour at the top (red \(top))")
        XCTAssertLessThan(coast, 0.04, "the coast point is not transparent (red \(coast))")
        XCTAssertGreaterThan(bottom, 0.07, "no reverse colour at the bottom (red \(bottom))")
        XCTAssertGreaterThan(top, coast + 0.1, "the gradient does not fade toward coast")
        XCTAssertGreaterThan(bottom, coast + 0.05, "reverse does not build from coast")
    }

    /// **A far seat's axis is mirrored**: their "top" is the screen's
    /// bottom, so full gas must paint there — an upside-down gradient would
    /// quietly reverse a flipped player's controls legend.
    func testAFlippedSeatsGradientIsMirrored() throws {
        let pad = DPadOverlay(
            origin: Vec2(93.5, 100), up: Vec2(0, 1), radius: 48,
            zone: zone, fullThrottleDepth: 0.3, coastDepth: 0.6,
            knob: .zero,
            stickBase: nil, thumb: nil, stickRadius: 60,
            input: CarInput(steer: 0, throttle: 1),
            color: Color(red: 1, green: 0, blue: 0),
            engaged: false)
        let view = Canvas { context, _ in
            OverlayRenderer.drawDPad(pad, into: &context)
        }
        .frame(width: zone.width, height: zone.height)
        .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: zone.width, height: zone.height)
        renderer.scale = 4
        let image = try XCTUnwrap(renderer.cgImage)
        let screenBottom = try red(image, x: 30, y: 197)  // their full gas
        let coast = try red(image, x: 30, y: 80)  // 60% down THEIR zone
        let screenTop = try red(image, x: 30, y: 4)  // their full reverse
        XCTAssertGreaterThan(screenBottom, coast + 0.08, "gas is not at the flipped seat's top")
        XCTAssertGreaterThan(screenTop, coast + 0.04, "reverse is not at the flipped seat's bottom")
    }

    /// **The steer is a solid full-height band** from the neutral column to
    /// the thumb's column — a line and a dot sat under the thumb where a
    /// thumb cannot see them; the band is readable above and below the
    /// finger. The full-lock rails frame how much lock is left.
    func testTheSteerBandIsSolidAndFullHeight() throws {
        let image = try render(base: Vec2(60, 100), thumb: Vec2(110, 100))
        // Mid-band, far above and far below the thumb's row.
        let high = try red(image, x: 85, y: 20)
        let low = try red(image, x: 85, y: 180)
        XCTAssertGreaterThan(high, 0.3, "the band is not full-height (red \(high))")
        XCTAssertGreaterThan(low, 0.3, "the band stops short (red \(low))")
        // Beyond the thumb's column: only the rail may paint, and faintly.
        let outside = try red(image, x: 140, y: 100)
        XCTAssertLessThan(outside, 0.25, "the band leaks past the thumb (red \(outside))")
        // The full-lock rail, a travel to the line's other side.
        let rail = try red(image, x: 120, y: 20)
        XCTAssertGreaterThan(rail, 0.1, "no full-lock rail (red \(rail))")
    }

    /// **Centred means no band**: a fill that never disappears would lie
    /// about a lock that is not there.
    func testNoBandWhenTheWheelIsCentred() throws {
        let image = try render(base: Vec2(110, 100), thumb: Vec2(110, 100))
        let sample = try red(image, x: 85, y: 100)
        XCTAssertLessThan(sample, 0.1, "a band is drawn while centred (red \(sample))")
    }
}
