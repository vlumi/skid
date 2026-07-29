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
