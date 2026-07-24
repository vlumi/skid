import Foundation

/// How continuous **height** (0 = ground, 1 = deck) maps to visual scale —
/// the single place road width and car size grow with elevation, so a ramp
/// widens and a car climbing it grows by one shared formula, in both the
/// editor and (eventually) the game renderer.
///
/// The growth factor is live-tunable (a Tuning slider), so the elevation feel
/// can be dialed on device without code changes.
public enum Elevation {
    /// Multiplier applied to road width and car scale at full height (1).
    /// Height 0 → 1.0×, height 1 → `deckScale`×, interpolated linearly by
    /// height. Default 1.2; overridable live.
    public static var deckScale: Double = 1.2

    /// The scale factor at a given height (0…1+): 1 at ground, `deckScale` at
    /// the deck, linear between. A jump can briefly exceed 1 (airborne), which
    /// simply scales up further — the same knob.
    public static func scale(atHeight h: Double) -> Double {
        1 + (deckScale - 1) * h
    }
}
