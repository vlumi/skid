import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **How many colors a car may wear, and what the reverse mark means.**
///
/// The first half of this is the test that should have been written before any accent
/// was added, and its absence is why a derived second tone shipped in a PR and had to
/// come out again: the tests measured base-against-base and nose-against-nose, but
/// never one car's base against *another car's* nose — which is the comparison a
/// player's eye actually makes.
@MainActor
final class CarLiveryRenderTests: XCTestCase {
    /// **A car wears ONE color, and that is a measured constraint.**
    ///
    /// Judged by the question that matters — can car A be told from car B — a car with
    /// two tones presents two patches, and confusion is any patch of one resembling
    /// any patch of another. Measured across all four vision types:
    ///
    /// | livery | worst cross-car distance |
    /// |---|---|
    /// | single tone | **ΔE 24.7** |
    /// | derived second tone | ΔE 4.6 |
    /// | the old white sheen | ΔE 3.7 |
    ///
    /// The budget is *tones*, not cars: nine mutually-distinct tones is already the
    /// edge of what color-blind-safe lightness spread allows, so eighteen do not
    /// exist. Two genuinely distinct hues per car measures fine at **four** cars
    /// (26.3) and cannot work at nine — so it belongs to a color picker that can
    /// bound choices by field size, not to arithmetic in the renderer.
    ///
    /// This measures the real rule, over whatever tones each car wears — so adding an
    /// accent later does not quietly bypass it. `tones(forSeat:)` is the single place
    /// to extend when a car gains a second color; the assertion then holds it to the
    /// same floor the palette was searched for.
    ///
    /// Sabotage: return `[paint, CarLivery-style lightened paint]` from `tones` and the
    /// worst case drops to ΔE 4.6, failing exactly as the reverted livery did.
    func testCarsStayDistinctAcrossEveryToneTheyWear() {
        /// Every color patch a player sees on this car. One entry today.
        func tones(forSeat seat: Int) -> [CarPalette.Paint] {
            [CarPalette.paints[seat]]
        }
        var worst = Double.infinity
        var offender = ""
        for vision in CarPalette.Paint.Vision.allCases {
            for i in CarPalette.paints.indices {
                for j in (i + 1)..<CarPalette.paints.count {
                    // Worst case over every pairing of one car's tones against the
                    // other's — a glance compares patches, not labeled regions.
                    for a in tones(forSeat: i) {
                        for b in tones(forSeat: j) {
                            let distance = a.seen(with: vision).distance(to: b.seen(with: vision))
                            if distance < worst {
                                worst = distance
                                offender = "seats \(i + 1)/\(j + 1) under \(vision)"
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(
            worst, 24.7,
            "cars are only ΔE \(Int(worst)) apart at worst (\(offender))")
    }

    /// The renderer draws from the measured palette, seat for seat — so a car's color
    /// is the one that was measured, not a nearby guess.
    func testTheDrawnPaletteIsTheMeasuredPalette() {
        XCTAssertEqual(TrackRenderer.carPalette.count, CarPalette.count)
        for seat in 0..<CarPalette.count {
            let paint = CarPalette.paints[seat]
            let expected = Color(red: paint.red, green: paint.green, blue: paint.blue)
            XCTAssertEqual(
                TrackRenderer.carPalette[seat], expected,
                "seat \(seat + 1) is not drawn in its measured paint")
        }
    }

    /// **The reverse cue answers "am I moving backwards", not "am I pointing there".**
    ///
    /// The distinction is the whole point of the mark, so it is tested with a car whose
    /// heading and velocity disagree — the drift case, where a facing cue says nothing
    /// useful. A car sliding sideways or backwards while pointed forwards is ordinary
    /// in this game.
    func testTheReverseCueFollowsMotionNotHeading() {
        var state = CarState(position: Vec2(0, 0), heading: 0)

        // Pointed +x, traveling -x: reversing.
        state.velocity = Vec2(-100, 0)
        XCTAssertLessThan(
            state.forwardSpeed, -TrackRenderer.reverseCueSpeed,
            "a car traveling opposite its heading must read as reversing")

        // Pointed +x, traveling +x: not reversing, however fast.
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
