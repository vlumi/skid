import Foundation
import Testing

@testable import SkidCore

/// **The default car colors are arithmetic, so they get measured.**
///
/// A palette tweak that quietly makes two cars look alike should fail a test rather
/// than a race. These pin the DEFAULTS only: players choose their own color in the
/// lobby and may deliberately pick something close to a rival, which is their call.
struct CarPaletteTests {
    /// Below roughly this, two cars read as the same color once they are small,
    /// moving and overlapping. The current shipped palette's worst pair is 21.
    private let readable = 24.0

    @Test func thereIsAColorForEverySlotOnTheGrid() {
        #expect(
            CarPalette.count == PieceCompiler.Grid.slots,
            "the palette and the grid must agree on how many cars a race holds")
    }

    /// **Every pair, in every vision type.** This is the test that matters: a
    /// hue-spread palette passes for trichromats and collapses to ΔE 8.7 under
    /// tritanopia, which is exactly the trap this guards.
    @Test func everyDefaultPairIsDistinguishableInEveryVisionType() {
        for vision in CarPalette.Paint.Vision.allCases {
            let seen = CarPalette.paints.map { $0.seen(with: vision) }
            for i in seen.indices {
                for j in seen.indices where j > i {
                    let delta = seen[i].distance(to: seen[j])
                    #expect(
                        delta >= readable,
                        "seats \(i) and \(j) are ΔE \(Int(delta)) apart under \(vision)")
                }
            }
        }
    }

    /// The property a player actually relies on: **I can find MY car.** Weaker than
    /// all-pairs, and the one the design commits to — nobody needs to identify the
    /// AI in fourth place.
    @Test func everySeatStandsClearOfTheField() {
        for vision in CarPalette.Paint.Vision.allCases {
            let seen = CarPalette.paints.map { $0.seen(with: vision) }
            for (index, mine) in seen.enumerated() {
                let nearest =
                    seen.enumerated()
                    .filter { $0.offset != index }
                    .map { mine.distance(to: $0.element) }
                    .min() ?? .infinity
                #expect(
                    nearest >= readable,
                    "seat \(index): nearest rival ΔE \(Int(nearest)) under \(vision)")
            }
        }
    }

    /// **Lightness spread is what carries CVD legibility**, since hue does not
    /// survive it. Pinned so a future "let's make them all vivid" pass cannot
    /// flatten it without failing here.
    @Test func theDefaultsSpanAWideRangeOfLightness() {
        let lightness = CarPalette.paints.map(\.lab.l)
        let spread = (lightness.max() ?? 0) - (lightness.min() ?? 0)
        #expect(spread > 55, "L* spans only \(Int(spread)); hue alone will not carry it")
    }

    /// The first four are the seats a 1–4 player game fills, so they should be
    /// **further** apart than the palette's general bar — that is the common case.
    @Test func theFirstFourSeatsAreTheFurthestApart() {
        let first = Array(CarPalette.paints.prefix(4))
        for vision in CarPalette.Paint.Vision.allCases {
            let seen = first.map { $0.seen(with: vision) }
            for i in seen.indices {
                for j in seen.indices where j > i {
                    #expect(
                        seen[i].distance(to: seen[j]) >= 40,
                        "seats \(i)/\(j) too close under \(vision) (the 1–4 case)")
                }
            }
        }
    }

    /// A sanity check on the measurement itself: identical paints are ΔE 0, and the
    /// simulation of normal vision changes nothing.
    @Test func theMeasurementItselfBehaves() {
        let paint = CarPalette.paints[0]
        #expect(paint.distance(to: paint) == 0)
        #expect(paint.seen(with: .normal) == paint)
        #expect(paint.distance(to: CarPalette.Paint(0, 0, 0)) > 50)
    }
}
