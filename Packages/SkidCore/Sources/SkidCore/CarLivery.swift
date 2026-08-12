import Foundation

/// **A car's two tones**, and the rule that keeps the light one at the front.
///
/// Lives in `SkidCore` beside `CarPalette` for the same reason: it is *arithmetic*.
/// The accent is not a second colour a player picks — it is **derived** from the
/// base by a lightness shift, and that is a deliberate restriction:
///
/// - **Facing must never invert.** The nose is the light tone on every car in the
///   field, so "bright end is the front" is a rule the player learns once. Let two
///   tones be picked freely and a dark-nosed car teaches the opposite, fighting
///   every other facing cue in the game.
/// - **One number identifies a car.** A livery is its base paint, so seat colour
///   stays one byte on the wire and one index in a picker — no pair table to agree
///   on, nothing to keep in step across devices.
/// - **Separation stays one-dimensional.** Cars are told apart by their BASE, which
///   is the large-area colour at race scale; the accent is detail. So the ΔE floor
///   `CarPaletteTests` guards keeps measuring exactly what it measured before,
///   rather than becoming a matrix of pairs.
///
/// A single-tone car is `shift: 0` — supported, and the same code path.
public enum CarLivery {
    /// How far the accent moves in **L\*** (CIELAB lightness), which is what makes
    /// the shift perceptually even rather than per-channel arithmetic. Lab is
    /// already here for the palette's separation measurements.
    ///
    /// 22 is a deliberate compromise, measured both ways: large enough that the two
    /// tones read as two at the tiny on-device car size, small enough that the
    /// accent still reads as *the same car's colour* rather than a second livery.
    public static let lightnessShift = 22.0

    /// The nose tone for a base paint: the base **darkened**, except for paints too
    /// dark to darken further, which are lightened instead.
    ///
    /// **Two invariants were tried and measured before this one.** Both failures are
    /// worth keeping, because both are invisible until the numbers are looked at:
    ///
    /// 1. *"The nose is always lighter."* Fails on the bright paints. Lime sits at
    ///    L\* 90.6 and yellow at 92.8, so a +22 shift has nowhere to go — measured
    ///    gaps of **1.9 and 4.3**, both noses landing near white.
    /// 2. *"Lighter, unless the paint is bright, then darker."* Fixed those two and
    ///    broke a different pair. Lightening converges toward white, discarding the
    ///    chroma that separates hues — violet (L\* 62.9) and pink (66.3) are the
    ///    palette's closest pair at ΔE 27.4 and both lifted to L\* 79, landing
    ///    **ΔE 0.6 apart**. The pair with least room to spare is the one it destroys.
    ///
    /// Darkening does not have that property: toward black, hues keep their relative
    /// chroma, so a pair stays as separated as it began. Hence **darken by default** —
    /// and the low-L\* paints (indigo 25.4, maroon 33.2, blue 33.9) go lighter because
    /// they have no room downward, which is the same headroom argument as (1) mirrored.
    ///
    /// The cue a player learns is *"the odd-toned end is the front"*, not *"the light
    /// end"* — a rule the palette can actually honour at nine cars.
    public static func nose(of base: CarPalette.Paint) -> CarPalette.Paint {
        base.lab.l < darkPivot
            ? base.lightened(by: lightnessShift) : base.lightened(by: -lightnessShift)
    }

    /// Below this L\*, a paint has too little headroom to darken and its nose goes
    /// lighter instead. 40 leaves the full shift available in both directions.
    public static let darkPivot = 40.0

    /// The tail tone: the base itself. The large rear area carries identity; the nose
    /// carries direction.
    public static func tail(of base: CarPalette.Paint) -> CarPalette.Paint { base }
}

extension CarPalette.Paint {
    /// This paint lifted by `delta` in L\*, holding hue and chroma as far as the
    /// gamut allows.
    ///
    /// Round-trips through Lab rather than scaling sRGB channels: multiplying
    /// channels toward 1 washes hue out unevenly (a blue lifts toward cyan), while a
    /// pure L\* move is the perceptual "same colour, lighter" a player expects.
    ///
    /// A negative `delta` darkens. Clamped to a usable L\* range at both ends: pure
    /// white and pure black both throw the hue away, and a nose that has lost its
    /// hue no longer belongs to its car. `CarLivery.nose(of:)` picks the direction
    /// with headroom, so in practice the clamp is slack — it is here so that an
    /// arbitrary shift stays in gamut rather than wrapping.
    public func lightened(by delta: Double) -> CarPalette.Paint {
        guard delta != 0 else { return self }
        let start = lab
        let target = min(97, max(6, start.l + delta))
        return CarPalette.Paint.from(
            lab: CarPalette.Paint.Lab(l: target, a: start.a, b: start.b))
    }
}

extension CarPalette.Paint {
    /// The inverse of `lab` — Lab back to sRGB, clamped into gamut.
    ///
    /// Needed because deriving a tone is a *round trip*: the palette measures in Lab
    /// and the renderer draws in sRGB, so a shift expressed perceptually has to come
    /// back. Uses the same D65 white point and sRGB transfer function as `lab`, so
    /// `from(lab: p.lab) == p` within float tolerance — pinned by a test, since an
    /// asymmetric pair here would quietly shift every colour in the game.
    public static func from(lab: CarPalette.Paint.Lab) -> CarPalette.Paint {
        let fy = (lab.l + 16) / 116
        let fx = fy + lab.a / 500
        let fz = fy - lab.b / 200
        func invF(_ t: Double) -> Double {
            let cube = t * t * t
            return cube > 0.008856 ? cube : (t - 16.0 / 116.0) / 7.787
        }
        let x = invF(fx) * 0.95047
        let y = invF(fy)
        let z = invF(fz) * 1.08883
        // Inverse of the XYZ matrix in `lab`.
        let r = x * 3.2406 + y * -1.5372 + z * -0.4986
        let g = x * -0.9689 + y * 1.8758 + z * 0.0415
        let b = x * 0.0557 + y * -0.2040 + z * 1.0570
        func encode(_ c: Double) -> Double {
            let clamped = min(1, max(0, c))
            return clamped <= 0.0031308
                ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }
        return CarPalette.Paint(encode(r), encode(g), encode(b))
    }
}
