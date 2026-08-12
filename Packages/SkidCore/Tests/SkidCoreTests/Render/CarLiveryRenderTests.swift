import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **What the renderer actually decides about a car's two tones.**
///
/// `GraphicsContext` cannot be inspected — a `Canvas` closure paints, it does not
/// report — so these test the *decisions* feeding the draw rather than pixels: which
/// tone each seat gets, and when the reverse cue turns on. That boundary is chosen
/// deliberately: the palette arithmetic is covered in `CarLiveryTests`, and asserting
/// on fills would need a rendering harness this repo does not have.
///
/// What that leaves unverified is the *drawing*: that the nose rect really is the
/// front half, and that the lamps sit at the tail. Those are visual, and go on device.
@MainActor
final class CarLiveryRenderTests: XCTestCase {
    /// Every seat in a full field gets a nose tone, and it is not the base tone.
    ///
    /// Guards the plumbing rather than the colours: the derivation could be perfect
    /// and the renderer could still pass `nil` for every car, which would silently
    /// ship single-tone cars with the sheen already deleted — a regression no
    /// `CarLivery` test can see.
    func testEverySeatGetsATwoToneBody() {
        for seat in 0..<CarPalette.count {
            let base = TrackRenderer.carPalette[seat]
            let nose = TrackRenderer.carNosePalette[seat]
            XCTAssertNotEqual(
                base, nose,
                "seat \(seat + 1) draws one tone; the facing cue is gone")
        }
    }

    /// The nose palette must line up with the base palette seat for seat — an
    /// off-by-one here would give every car a neighbour's accent, which reads as a
    /// colour bug rather than a livery.
    func testTheNosePaletteIsSeatAlignedWithTheBasePalette() {
        XCTAssertEqual(TrackRenderer.carNosePalette.count, TrackRenderer.carPalette.count)
        for seat in 0..<CarPalette.count {
            let expected = CarLivery.nose(of: CarPalette.paints[seat])
            let asDrawn = Color(red: expected.red, green: expected.green, blue: expected.blue)
            XCTAssertEqual(
                TrackRenderer.carNosePalette[seat], asDrawn,
                "seat \(seat + 1)'s nose is not its own paint's derived tone")
        }
    }

    /// **The reverse cue answers "am I moving backwards", not "am I pointing there".**
    ///
    /// The distinction is the whole point of the mark, so it is tested with a car
    /// whose heading and velocity disagree — the drift case, where a facing cue says
    /// nothing useful. A car sliding sideways or backwards while pointed forwards is
    /// ordinary in this game.
    func testTheReverseCueFollowsMotionNotHeading() {
        var state = CarState(position: Vec2(0, 0), heading: 0)

        // Pointed +x, travelling -x: reversing.
        state.velocity = Vec2(-100, 0)
        XCTAssertLessThan(
            state.forwardSpeed, -TrackRenderer.reverseCueSpeed,
            "a car travelling opposite its heading must read as reversing")

        // Pointed +x, travelling +x: not reversing, however fast.
        state.velocity = Vec2(400, 0)
        XCTAssertGreaterThan(state.forwardSpeed, 0, "forward motion must not read as reverse")

        // Pointed +x, sliding sideways: not reversing. This is the case a naive
        // "velocity disagrees with heading" test would get wrong.
        state.velocity = Vec2(0, 300)
        XCTAssertEqual(
            state.forwardSpeed, 0, accuracy: 0.001,
            "a pure sideways slide is neither forward nor reverse")
    }

    /// The cue has a dead band, and it must be wide enough to swallow the jitter of a
    /// car resting against a wall — otherwise the lamps flicker and read as a fault.
    func testTheReverseCueIgnoresCreepingSpeeds() {
        var state = CarState(position: Vec2(0, 0), heading: 0)
        state.velocity = Vec2(-1, 0)
        XCTAssertGreaterThan(
            state.forwardSpeed, -TrackRenderer.reverseCueSpeed,
            "a car creeping backwards must not light its reversing lamps")
        XCTAssertGreaterThan(
            TrackRenderer.reverseCueSpeed, 5,
            "the dead band is too narrow to absorb wall jitter")
        // …and well under the speed reverse gear actually reaches, or the cue would
        // never appear during real reversing.
        XCTAssertLessThan(
            TrackRenderer.reverseCueSpeed, CarTuning().reverseMaxSpeed / 4,
            "the dead band is so wide the cue would rarely show")
    }
}
