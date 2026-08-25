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
            zone: zone, coastDepth: 0.6,
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
            zone: zone, coastDepth: 0.6,
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

    /// **The neutral line is full-height and the gap bar reaches the thumb.**
    func testTheNeutralLineAndGapAreDrawn() throws {
        let image = try render(base: Vec2(60, 100), thumb: Vec2(110, 100))
        // The line, far from the thumb's row — full height.
        let lineHigh = try red(image, x: 60, y: 20)
        let lineLow = try red(image, x: 60, y: 180)
        XCTAssertGreaterThan(lineHigh, 0.5, "the neutral line is not full-height (red \(lineHigh))")
        XCTAssertGreaterThan(lineLow, 0.5, "the neutral line stops short (red \(lineLow))")
        // Mid-gap at the thumb's row: the steer bar.
        let gap = try red(image, x: 85, y: 100)
        XCTAssertGreaterThan(gap, 0.5, "the steer gap is not drawn (red \(gap))")
        // The full-lock rail, a travel to the line's other side.
        let rail = try red(image, x: 120, y: 20)
        XCTAssertGreaterThan(rail, 0.1, "no full-lock rail (red \(rail))")
    }

    /// **Centred means no gap**: a bar that never disappears would lie about
    /// a lock that is not there.
    func testNoGapWhenTheLineIsUnderTheThumb() throws {
        let image = try render(base: Vec2(110, 100), thumb: Vec2(110, 100))
        let sample = try red(image, x: 85, y: 100)
        XCTAssertLessThan(sample, 0.1, "a gap is drawn while centred (red \(sample))")
    }
}
