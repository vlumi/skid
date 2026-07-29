import Foundation

/// **The fitting piece**: a curve, a straight, and a mirrored curve — a smooth
/// lateral jog that enters and leaves on the same heading.
///
/// It exists because the quantized catalog cannot always close a loop. Axis
/// straights displace by whole units; diagonal ones by `n·√2/2`; only 45° arcs
/// mix the two. So a ring using both families has to drive two independent
/// quantities to zero at once — the integer part and the √2 part — with straight
/// lengths as the only knobs, which turns designing a track into solving
/// simultaneous equations. Measured on a real mixed figure-eight, the heading
/// closes fine and a gap of `(2·√2/2, 2−√2)U` is left over, which no catalog
/// piece can absorb.
///
/// **This is the one piece whose geometry is not exact.** Everything else lives
/// in `Coord`'s ring — `(a + b√2)/2` with integer parts — so loop closure and
/// port mating need no epsilon. A free arc angle cannot: `sin(29.28°)` is not in
/// the ring. The fitter is allowed to be inexact because it is *defined* by its
/// endpoints: it is the shape that reaches the pose it was solved for, so closure
/// is true by construction rather than by comparison. Its residual is ~1e-12
/// units, twelve orders of magnitude below a device pixel and ten below the
/// tightest gameplay tolerance.
///
/// **Its solved parameters are stored, not re-derived.** `sin` and `atan2` are
/// not required to be correctly rounded, so two devices re-solving the same
/// fitter could differ by an ULP — and deterministic lockstep (see AGENTS.md) has
/// no tolerance for that. Storing the answer also frees the piece from depending
/// on its neighbours, which is what allows more than one per track and allows
/// deleting other pieces while one exists.
public struct Fitter: Equatable, Sendable, Codable {
    /// Arc radius in world units — one of the catalog's three, so a fitter still
    /// looks like the rest of the road.
    public var radius: Double
    /// How far each arc turns, in radians. Equal and opposite, so the piece
    /// leaves on the heading it entered. **Zero is legal and useful**: at zero
    /// both arcs vanish and the piece is a plain straight of `length`, which is
    /// what lets a fitter absorb a purely longitudinal gap.
    public var angle: Double
    /// The straight between the arcs, in world units.
    public var length: Double
    /// Which way the jog steps: `true` = to the entry heading's left.
    public var stepsLeft: Bool

    public init(radius: Double, angle: Double, length: Double, stepsLeft: Bool) {
        self.radius = radius
        self.angle = angle
        self.length = length
        self.stepsLeft = stepsLeft
    }

    /// Displacement from entry to exit, in the ENTRY's frame: `x` forward, `y` to
    /// the entry heading's left. The exit heading equals the entry heading.
    public var displacement: (forward: Double, left: Double) {
        // Arc 1 turns by `angle`, the straight runs along that heading, arc 2
        // turns back. In the entry frame, with s = sin, c = cos:
        //   arc1     = (R·sinθ,  side·R·(1−cosθ))
        //   straight = length · (cosθ, side·sinθ)
        //   arc2     = (R·sinθ,  side·R·(1−cosθ))     [same, by symmetry]
        let side = stepsLeft ? 1.0 : -1.0
        let forward = 2 * radius * sin(angle) + length * cos(angle)
        let left = side * (2 * radius * (1 - cos(angle)) + length * sin(angle))
        return (forward, left)
    }

    /// Centerline length — what the piece costs in road.
    public var arcLength: Double { 2 * radius * angle + length }
}

extension Fitter {
    /// The radii a fitter may use — the catalog's own three, so it still looks
    /// like the rest of the road.
    public static var radii: [Double] {
        [
            Double(PieceCatalog.tightRadius), Double(PieceCatalog.mediumRadius),
            Double(PieceCatalog.sweepRadius),
        ]
    }

    /// Largest arc turn a fitter may use. Beyond a quarter turn the "smooth jog"
    /// reads as a pair of corners instead.
    public static let maxAngle = Double.pi / 2

    /// **The shortest fitter reaching `(forward, left)` in the entry frame**, or
    /// nil if the shape cannot.
    ///
    /// Closed form, not a search. Writing `F` for forward and `T` for |left|:
    ///
    ///     F = 2R·sin θ + L·cos θ
    ///     T = 2R·(1 − cos θ) + L·sin θ
    ///
    /// Eliminating `L` and multiplying through by `cos θ` collapses to
    ///
    ///     F·sin θ + (2R − T)·cos θ = 2R
    ///
    /// which is `A·sin θ + B·cos θ = C` — solvable directly as
    /// `θ = atan2(A, B) ± acos(C / hypot(A, B))`. Both roots are checked, the
    /// shortest valid one wins, and `L` follows from the first equation.
    ///
    /// Unreachable gaps fall out of the same arithmetic rather than being
    /// special-cased: `|C| > hypot(A, B)` means no angle exists, and a negative
    /// `L` means the arcs alone already overshoot. That is the dead zone — gaps
    /// too short to fit two arcs plus a straight, which need no fitter anyway
    /// because they are within reach of ordinary pieces.
    public static func solving(
        forward: Double, left: Double, radii: [Double] = Fitter.radii,
        maxLength: Double = Fitter.maxLength
    ) -> Fitter? {
        var best: Fitter?
        for radius in radii {
            for candidate in candidates(
                forward: forward, left: left, radius: radius, maxLength: maxLength)
            {
                // Snapped to the encodable grid HERE, so the shape that closes
                // the loop is the shape a decoded code reproduces exactly.
                let snapped = candidate.quantized
                if best == nil || snapped.arcLength < best!.arcLength {
                    best = snapped
                }
            }
        }
        return best
    }

    /// Both roots for one radius, keeping the valid ones.
    private static func candidates(
        forward: Double, left: Double, radius: Double, maxLength: Double
    ) -> [Fitter] {
        let target = abs(left)
        let a = forward
        let b = 2 * radius - target
        let c = 2 * radius
        let hypotenuse = (a * a + b * b).squareRoot()
        guard hypotenuse > 1e-12, abs(c / hypotenuse) <= 1 else { return [] }
        let base = atan2(a, b)
        let offset = acos(c / hypotenuse)
        var out: [Fitter] = []
        for root in [base - offset, base + offset] {
            // A root a hair below zero IS the zero-angle case (the plain
            // straight) arriving as -1e-17; clamping keeps it rather than
            // discarding the one shape that closes a purely forward gap.
            let angle = abs(root) < 1e-9 ? 0 : root
            guard angle >= 0, angle <= maxAngle else { continue }
            guard cos(angle) > 1e-9 else { continue }
            let length = (forward - 2 * radius * sin(angle)) / cos(angle)
            guard length >= -1e-9, length <= maxLength else { continue }
            let fitter = Fitter(
                radius: radius, angle: angle, length: max(0, length),
                stepsLeft: left >= 0)
            // Verify rather than trust: the algebra above assumed cos θ ≠ 0 and
            // dropped a sign, so confirm the shape really lands on the target.
            let step = fitter.displacement
            guard abs(step.forward - forward) < 1e-6, abs(step.left - left) < 1e-6
            else { continue }
            out.append(fitter)
        }
        return out
    }
}

extension Fitter {
    /// **Quantization is applied at SOLVE time, not at encode time.**
    ///
    /// The stored numbers have to be the only numbers, or the authoring device
    /// and a device that decodes the code would walk slightly different shapes —
    /// which deterministic lockstep cannot tolerate. So a solved fitter is
    /// snapped to the encodable grid immediately, and the *snapped* shape is what
    /// closes the loop, gets drawn, and gets driven. Encoding is then lossless by
    /// construction.
    ///
    /// 24 bits each for angle and length: the angle step is ~5e-6°, the length
    /// step ~6e-5 units. The worst positional error is four orders of magnitude
    /// below `Track.surfaceTolerance` and five below a device pixel, so the
    /// snapping is invisible — but it is a real change to the shape, which is why
    /// it happens before anything measures the shape.
    public static let angleSteps = 1 << 24
    public static let lengthSteps = 1 << 24
    /// The longest middle straight a fitter may store, and so the range the
    /// length quantization spans.
    public static let maxLength = 8 * Double(PieceCatalog.unit)

    /// This fitter snapped to the encodable grid.
    public var quantized: Fitter {
        Fitter(
            radius: radius,
            angle: Self.dequantizedAngle(Self.quantizedAngle(angle)),
            length: Self.dequantizedLength(Self.quantizedLength(length)),
            stepsLeft: stepsLeft)
    }

    static func quantizedAngle(_ angle: Double) -> Int {
        let clamped = min(max(angle, 0), maxAngle)
        return Int((clamped / maxAngle * Double(angleSteps - 1)).rounded())
    }

    static func dequantizedAngle(_ steps: Int) -> Double {
        Double(steps) / Double(angleSteps - 1) * maxAngle
    }

    static func quantizedLength(_ length: Double) -> Int {
        let clamped = min(max(length, 0), maxLength)
        return Int((clamped / maxLength * Double(lengthSteps - 1)).rounded())
    }

    static func dequantizedLength(_ steps: Int) -> Double {
        Double(steps) / Double(lengthSteps - 1) * maxLength
    }

    /// Index of this fitter's radius in `Fitter.radii`, for encoding.
    var radiusIndex: Int? {
        Self.radii.firstIndex { abs($0 - radius) < 1e-9 }
    }
}
