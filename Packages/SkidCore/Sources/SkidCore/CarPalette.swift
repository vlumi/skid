import Foundation

/// **The car colors**, chosen so a player can find their own car — in any vision
/// type, on any surface.
///
/// Lives in `SkidCore` rather than beside the renderer because it is *arithmetic*:
/// perceptual separation is measurable, and `CarPaletteTests` measures it. A color
/// tweak that quietly makes two cars look alike should fail a test, not a race.
public enum CarPalette {
    /// One car color as plain sRGB components, 0…1. Deliberately not `SwiftUI.Color`
    /// — SkidCore has no UI dependency, and the numbers are the point.
    public struct Paint: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Nine paints, in **seat order**.
    ///
    /// **Chosen for color-blind legibility, which rules out the obvious answer.** A
    /// hue-spread nine (red/orange/yellow/green/teal/cyan/blue/purple/magenta)
    /// measures a comfortable ΔE 33 in normal vision and then collapses to **8.7**
    /// under tritanopia — nine *hues* cannot stay distinct once hue discrimination
    /// does. What survives is **lightness** spread, so these run L* 25…93 and hold
    /// ≥24.7 in normal, protan, deutan AND tritan simulation.
    ///
    /// **Seat order is by separation, not by hue.** The first four are the seats a
    /// 1–4 player game actually fills, so they are the four furthest apart; listing
    /// by hue would have put three warm colors in the first three seats.
    ///
    /// What this palette deliberately does NOT try to do:
    ///
    /// - **Carry contrast against every surface.** Cars glow (see the renderer), and
    ///   that is what generalises to road surfaces yet to exist — snow, gravel.
    /// - **Make all nine mutually obvious.** The goal is finding *your* car; nobody
    ///   needs to identify the AI in fourth. Every seat sits ≥24.7 from its nearest
    ///   rival, which is the number that matters under that rule.
    /// - **Mark out local players.** Desaturating the others wrecks it — measured:
    ///   worst pair 24.7 → 6.5 at 55% saturation, and desaturation *raises* L*,
    ///   flattening the very spread this rests on. A ring or the seat number does
    ///   that job. "Local" is also a per-screen property: under networking the same
    ///   car is local on one device and remote on another.
    /// Order found by search, not by hand: seats 1–4 hold the four colors whose
    /// worst pair is furthest apart (ΔE 49.9 across all vision types), then each
    /// next seat is the one that degrades the set least. Hand-ordering these by
    /// lightness gave the common 1–4 case only 30.
    public static let paints: [Paint] = [
        Paint(0.27, 0.05, 0.95),  // blue      L* 34
        Paint(0.40, 1.00, 0.70),  // lime      L* 91
        Paint(0.85, 0.40, 1.00),  // violet    L* 63
        Paint(0.62, 0.03, 0.18),  // maroon    L* 33
        Paint(0.95, 0.95, 0.05),  // yellow    L* 93
        Paint(0.47, 0.62, 0.03),  // olive     L* 60
        Paint(0.33, 0.03, 0.62),  // indigo    L* 25
        Paint(0.95, 0.05, 0.50),  // magenta   L* 53
        Paint(1.00, 0.40, 0.85),  // pink      L* 66
    ]

    /// How many cars a race can hold — the palette's own limit, which is also the
    /// grid's (`PieceCompiler.Grid.slots`). Kept in step by a test.
    public static var count: Int { paints.count }
}

// MARK: - Perceptual measurement

extension CarPalette.Paint {
    /// A color in **CIELAB**: `l` is lightness, `a`/`b` the opponent axes.
    public struct Lab: Equatable, Sendable {
        public var l: Double
        public var a: Double
        public var b: Double
    }

    /// This paint in **CIELAB**, where euclidean distance approximates how different
    /// two colors *look* — which is the only useful way to ask "can a player tell
    /// these apart". RGB distance says red and brown are far apart; the eye disagrees.
    public var lab: Lab {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linear(red), g = linear(green), b = linear(blue)
        let x = r * 0.4124 + g * 0.3576 + b * 0.1805
        let y = r * 0.2126 + g * 0.7152 + b * 0.0722
        let z = r * 0.0193 + g * 0.1192 + b * 0.9505
        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3) : 7.787 * t + 16.0 / 116
        }
        let fx = f(x / 0.95047), fy = f(y), fz = f(z / 1.08883)
        return Lab(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    /// Perceptual distance to another paint (CIELAB ΔE76). Below roughly 20 two cars
    /// read as the same color once they are small, moving and overlapping.
    public func distance(to other: CarPalette.Paint) -> Double {
        let a = lab, b = other.lab
        return
            ((a.l - b.l) * (a.l - b.l) + (a.a - b.a) * (a.a - b.a)
            + (a.b - b.b) * (a.b - b.b)).squareRoot()
    }

    /// The three common kinds of color-vision deficiency, for simulation.
    public enum Vision: CaseIterable, Sendable {
        case normal
        /// Red-blind (~1% of men).
        case protanopia
        /// Green-blind (~1% of men, the commonest).
        case deuteranopia
        /// Blue-blind (rare).
        case tritanopia
    }

    /// This paint **as seen** with the given vision, via the standard LMS-space
    /// simulation. Used by the tests: a palette that only works for trichromats is
    /// not an accessible palette.
    public func seen(with vision: Vision) -> CarPalette.Paint {
        guard vision != .normal else { return self }
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func encode(_ c: Double) -> Double {
            let clamped = min(1, max(0, c))
            return clamped <= 0.0031308
                ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }
        let r = linear(red), g = linear(green), b = linear(blue)
        var long = 0.31399 * r + 0.63951 * g + 0.04649 * b
        var middle = 0.15537 * r + 0.75789 * g + 0.08670 * b
        var short = 0.01775 * r + 0.10945 * g + 0.87116 * b
        switch vision {
        case .protanopia: long = 1.05118 * middle - 0.05116 * short
        case .deuteranopia: middle = 0.95130 * long + 0.04865 * short
        case .tritanopia: short = -0.86744 * long + 1.86727 * middle
        case .normal: break
        }
        return CarPalette.Paint(
            encode(5.47221 * long - 4.64196 * middle + 0.16963 * short),
            encode(-1.12524 * long + 2.29317 * middle - 0.16789 * short),
            encode(0.02980 * long - 0.19318 * middle + 1.16364 * short))
    }
}
