import Foundation

/// A solid barrier segment cars bounce off. Sits at a **height**: a car at a
/// very different height passes it freely, so a deck rail never blocks the road
/// underneath the bridge.
public struct Wall: Equatable, Sendable, Codable {
    /// What this barrier *is*, so the renderer can tell a visible structure from
    /// an invisible limit. Physics treats them identically.
    public enum Kind: String, Equatable, Sendable, Codable {
        /// A guard rail along a bridge deck or ramp — drawn as a blue barrier.
        case rail
        /// The map boundary. Enforced, never drawn: a painted rectangle around
        /// the whole playfield would look like scenery that isn't there.
        case boundary
        /// A one-way level seal: blocks every car BELOW its height, passes
        /// everyone at or above — the wall under a raised road's mouth. Its
        /// whole job is "you may not enter from a level below this one", so
        /// unlike a rail it has no top a car could be over. (A tunnel mouth
        /// will want the mirror image as its own case.)
        case gate
        /// **The earth under a climbing piece**, from the ground up to the road
        /// it carries. Stops a car below from driving into the flank of a ramp.
        ///
        /// Separate from `rail` because they are separate things doing separate
        /// jobs, which one wall could not do at once: a railing guards the road
        /// it edges, an embankment fills the space beneath it. Conflating them
        /// meant a ramp's side barrier was a railing stretched down to the
        /// floor, and every attempt to fix one end broke the other.
        case embankment
    }

    public var a: Vec2
    public var b: Vec2
    /// 0 = ground, 1 = deck. A boundary fence spans every height (see `kind`).
    public var height: Double
    public var kind: Kind

    /// **Which way this barrier's structure stands**, as a unit vector pointing
    /// away from the road it guards — the direction its bulk occupies.
    ///
    /// A rail is a line here but a BAND on screen (`kerbBand` outboard of the
    /// asphalt), so a car meeting it from that side must stop against the band's
    /// face rather than the line's, and the collision needs to know which side
    /// that is. It cannot be derived: comparing distance to the centerline costs
    /// a full search per wall per tick, and "away from the middle of the map" is
    /// a coin flip on a track that curls back on itself — measured 192 wrong out
    /// of 430 rails on the clover. The compiler builds each edge's rails already
    /// knowing the direction, so it simply records it.
    ///
    /// `.zero` means "no side" — a barrier with no bulk to stand clear of (the
    /// map boundary, a level seal), and the case older data decodes to.
    public var outward: Vec2 = .zero

    /// **Whether this wall edges a CLIMBING stretch of road**, as opposed to a
    /// flat run at one level.
    ///
    /// It decides where a railing's protection starts, and it cannot be derived
    /// from `height`: a rail at 0.96 is a deck that sags on an S-curve (its road
    /// is level 1, so the ground must pass beneath), while a rail at 0.75 is the
    /// middle of a climb (its road is right there, so a car at 0.5 must be held).
    /// Same height range, opposite answers. The compiler knows which it is built
    /// from — the same `climb != 0` that decides whether to lay an embankment —
    /// so, like `outward`, it simply records it.
    ///
    /// `false` is the flat reading, and what older data decodes to.
    public var onClimb = false

    /// **The height this wall's structure stands ON**, for earth that fills a
    /// space rather than edging a road.
    ///
    /// An embankment is solid from here up to `height`. It used to be solid from
    /// the GROUND up, which was indistinguishable while there was one deck —
    /// nothing could be underneath a ramp. With three storeys a 2→3 ramp's earth
    /// spanned 0…3 and walled off the level-1 road passing beneath it: a track that
    /// built fine and could not be driven.
    ///
    /// A ramp stands on the storey it climbs from, so that is what the compiler
    /// records. `0` is the ground, and what older data decodes to.
    public var base = 0.0

    public init(
        from a: Vec2, to b: Vec2, height: Double = 0, kind: Kind = .rail,
        outward: Vec2 = .zero, onClimb: Bool = false, base: Double = 0
    ) {
        self.a = a
        self.b = b
        self.height = height
        self.kind = kind
        self.outward = outward
        self.onClimb = onClimb
        self.base = base
    }

}
