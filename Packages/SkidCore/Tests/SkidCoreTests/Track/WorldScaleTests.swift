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

    // MARK: - Imperial

    /// **Metric is the default**, everywhere the label is asked without a system.
    @Test func metricIsTheDefault() {
        #expect(
            WorldScale.distanceLabel(units: 5141)
                == WorldScale.distanceLabel(
                    units: 5141, in: .metric))
        #expect(
            WorldScale.speedLabel(unitsPerSecond: 520)
                == WorldScale.speedLabel(
                    unitsPerSecond: 520, in: .metric))
    }

    /// The same journey, told two ways — and the imperial numbers have to be a
    /// correct conversion of the metric ones, not a second invented scale.
    @Test func imperialIsTheSameDistanceInOtherWords() {
        let lap = 5141.0
        let metres = WorldScale.metres(lap)
        let feet = WorldScale.feet(lap)
        #expect(abs(feet / metres - 3.280_84) < 1e-6)
        let kph = WorldScale.kilometresPerHour(520)
        let mph = WorldScale.milesPerHour(520)
        #expect(abs(kph / mph - 1.609_344) < 1e-6)
    }

    @Test func imperialLabelsNameImperialUnits() {
        #expect(WorldScale.distanceLabel(units: 5141, in: .imperial).hasSuffix(" ft"))
        #expect(WorldScale.speedLabel(unitsPerSecond: 520, in: .imperial).hasSuffix(" mph"))
        // A long lap switches to miles rather than printing five digits of feet.
        let long = WorldScale.distanceLabel(units: 100_000, in: .imperial)
        #expect(long.hasSuffix(" mi"), "a very long lap should read in miles, not \(long)")
    }

    /// The stock car should sound fast in BOTH systems — 155 mph is the number
    /// an imperial player reads, and it has to be as satisfying as 250 km/h.
    @Test func theStockCarSoundsFastInImperialToo() {
        let mph = WorldScale.milesPerHour(CarTuning().maxSpeed)
        #expect(mph > 140 && mph < 170, "reads \(Int(mph)) mph")
    }

    /// An unreadable stored value falls back to metric rather than crashing or
    /// picking imperial — the default has to survive a bad defaults entry.
    @Test func anUnknownStoredSystemFallsBackToMetric() {
        #expect(WorldScale.Units(rawValue: "furlongs") == nil)
        #expect(WorldScale.Units(rawValue: "metric") == .metric)
        #expect(WorldScale.Units(rawValue: "imperial") == .imperial)
    }

    // MARK: - The per-player speedometer

    /// **Reverse reads negative.** The readout is the speed along the car's own
    /// nose, not the magnitude of its velocity — a magnitude cannot tell going
    /// backwards from going forwards, and "didn't notice I was reversing" is a
    /// reported confusion.
    @Test func reversingReadsAsANegativeSpeed() {
        var state = CarState(position: .zero, velocity: Vec2(300, 0))
        state.heading = 0  // nose along +x
        let forward = WorldScale.kilometresPerHour(state.velocity.dot(state.forward))
        #expect(forward > 0)

        state.velocity = Vec2(-120, 0)  // rolling back, still facing +x
        let reversing = WorldScale.kilometresPerHour(state.velocity.dot(state.forward))
        #expect(reversing < 0, "reversing read as \(Int(reversing))")
        // The magnitude would have reported this as positive — the whole point.
        #expect(WorldScale.kilometresPerHour(state.velocity.length) > 0)
        #expect(
            WorldScale.speedLabel(unitsPerSecond: state.velocity.dot(state.forward))
                .hasPrefix("-"))
    }

    /// A pure sideways slide has no forward progress, so it reads zero. Honest
    /// rather than obviously right — worth knowing it is deliberate if a drift
    /// showing 0 ever looks wrong on device.
    @Test func aSidewaysSlideReadsZero() {
        var state = CarState(position: .zero, velocity: Vec2(0, 260))
        state.heading = 0
        #expect(abs(state.velocity.dot(state.forward)) < 1e-9)
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
