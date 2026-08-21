import Foundation
import Testing

@testable import SkidCore

/// **How world units read as distance and speed.**
///
/// The scale is chosen for FEEL — the world has no true one — so these tests pin
/// the two things that matter: the arithmetic is right, and the numbers it
/// produces are the fast-sounding ones the scale was picked for. If a tuning
/// change or a new scale makes the stock car top out somewhere silly, that is
/// worth failing over rather than discovering on a screenshot.
struct WorldScaleTests {
    @Test func theStockCarTopsOutAtAFastRoundNumber() {
        let top = WorldScale.kilometresPerHour(CarTuning().maxSpeed)
        #expect(
            abs(top - 250) < 1,
            "the scale exists to make this a satisfying number; it reads \(Int(top)) km/h")
    }

    /// A lap of every built-in reads as a plausible circuit rather than as a
    /// driveway or a motorway.
    @Test func everyBuiltInLapReadsAsACircuit() throws {
        for builtin in TrackLibrary.builtins {
            let stats = try #require(
                TrackStats.of(layout: try TrackCode.decode(builtin.code)))
            let metres = WorldScale.metres(stats.length)
            #expect(
                metres > 200 && metres < 2000,
                "\(builtin.name) reads as \(Int(metres)) m")
        }
    }

    @Test func conversionsAreExactAndInvertible() {
        #expect(WorldScale.metres(WorldScale.unitsPerMetre) == 1)
        #expect(WorldScale.metres(0) == 0)
        #expect(WorldScale.kilometresPerHour(0) == 0)
        // 1 m/s is 3.6 km/h, whatever the scale.
        #expect(abs(WorldScale.kilometresPerHour(WorldScale.unitsPerMetre) - 3.6) < 1e-9)
    }

    /// **No raw units reach a player.** Distances carry "m" or "km" and speeds
    /// carry "km/h" — reading "5141 long" was the report that started this.
    @Test func labelsAlwaysNameARealUnit() {
        #expect(WorldScale.distanceLabel(units: 5141).hasSuffix(" m"))
        #expect(WorldScale.speedLabel(unitsPerSecond: 520).hasSuffix(" km/h"))
        // A lap long enough to want kilometres switches over rather than
        // printing four digits of metres.
        let long = WorldScale.distanceLabel(units: WorldScale.unitsPerMetre * 12_500)
        #expect(long.hasSuffix(" km"), "a very long lap should read in km, not \(long)")
        #expect(long.contains("12.5"))
    }

    /// The clover's measured quick lap (14.30 s over its own length) should
    /// average a speed that sounds like racing — the whole point of the scale.
    @Test func aQuickLapAveragesARacingSpeed() throws {
        let clover = try #require(TrackLibrary.builtins.first { $0.id == "clover" })
        let stats = try #require(TrackStats.of(layout: try TrackCode.decode(clover.code)))
        let average = WorldScale.kilometresPerHour(stats.length / 14.30)
        #expect(average > 120 && average < 250, "a quick lap averages \(Int(average)) km/h")
    }
}
