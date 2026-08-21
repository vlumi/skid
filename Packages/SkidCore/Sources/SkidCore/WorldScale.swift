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

    /// A distance for display: metres, or kilometres once it would need four
    /// digits. Rounded, since nobody needs a lap to the centimetre.
    public static func distanceLabel(units: Double) -> String {
        let metres = metres(units)
        if metres >= 1000 {
            return String(format: "%.1f km", metres / 1000)
        }
        return "\(Int(metres.rounded())) m"
    }

    /// A speed for display, in km/h.
    public static func speedLabel(unitsPerSecond: Double) -> String {
        "\(Int(kilometresPerHour(unitsPerSecond).rounded())) km/h"
    }
}
