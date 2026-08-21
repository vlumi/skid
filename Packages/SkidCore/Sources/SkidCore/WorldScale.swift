import Foundation

/// **How world units read as distance and speed.**
///
/// The sim has no physical scale — a unit is a unit, and speed is units per
/// second (`CarTuning.maxSpeed` is 520, the tick is 1/60 s). That is the right
/// model to compute in, and the wrong thing to show: "5141 long" and "top speed
/// 517" mean nothing to anyone, and "is 520 fast?" has no answer.
///
/// **The scale is chosen for FEEL, not for accuracy.** There is no true answer to
/// pick — the car is drawn deliberately chunky and arcade, so no single number
/// satisfies both its proportions and the road's width. So it is chosen to make
/// the numbers sound fast while staying self-consistent, which is what a racing
/// game's speedometer is for in the first place.
///
/// At **7.5 units per metre** the stock car tops out at a round **250 km/h**, a
/// lap of the built-ins reads 365–685 m, and a quick lap of the clover averages
/// 173 km/h. Every one of those is a number a player can feel. (Taken literally
/// it also makes the car 4.5 m and the road 16 m wide — generous, but nobody
/// measures the tarmac.)
///
/// One definition, in the core, because the editor's stats, the test drive's
/// readout and the race HUD must not each invent their own.
public enum WorldScale {
    /// World units per metre.
    public static let unitsPerMetre = 7.5

    /// A distance in world units, as metres.
    public static func metres(_ units: Double) -> Double { units / unitsPerMetre }

    /// A speed in units per second, as km/h.
    public static func kilometresPerHour(_ unitsPerSecond: Double) -> Double {
        unitsPerSecond / unitsPerMetre * 3.6
    }

    /// Which units a player reads. **Metric by default**, since most of the
    /// world is; imperial is a preference, not a locale guess — somebody who
    /// wants miles per hour wants them wherever they are.
    public enum Units: String, CaseIterable, Sendable, Codable {
        case metric
        case imperial
    }

    /// A distance in world units, as feet.
    public static func feet(_ units: Double) -> Double { metres(units) * 3.280_84 }

    /// A speed in units per second, as mph.
    public static func milesPerHour(_ unitsPerSecond: Double) -> Double {
        kilometresPerHour(unitsPerSecond) / 1.609_344
    }

    /// A distance for display: metres/kilometres, or feet/miles — switching to
    /// the larger unit once the smaller one would need four digits. Rounded,
    /// since nobody needs a lap to the centimetre.
    public static func distanceLabel(units: Double, in system: Units = .metric) -> String {
        switch system {
        case .metric:
            let metres = metres(units)
            return metres >= 1000
                ? String(format: "%.1f km", metres / 1000)
                : "\(Int(metres.rounded())) m"
        case .imperial:
            let feet = feet(units)
            // A mile is 5280 ft, so the same "four digits is too many" rule puts
            // the switch a little under one mile — which reads better than
            // "0.3 mi" for a lap that is plainly a few hundred yards.
            return feet >= 3000
                ? String(format: "%.1f mi", feet / 5280)
                : "\(Int(feet.rounded())) ft"
        }
    }

    /// A speed for display, in km/h or mph.
    public static func speedLabel(
        unitsPerSecond: Double, in system: Units = .metric
    ) -> String {
        switch system {
        case .metric:
            return "\(Int(kilometresPerHour(unitsPerSecond).rounded())) km/h"
        case .imperial:
            return "\(Int(milesPerHour(unitsPerSecond).rounded())) mph"
        }
    }
}
