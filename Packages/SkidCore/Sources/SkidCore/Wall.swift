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

    /// Whether this wall stops this car.
    ///
    /// A boundary fence stops everyone. A **rail** guards one stretch of road, and
    /// it blocks from **its own level's floor up to its own height** — that is,
    /// from `trunc(height)` to `height`.
    ///
    /// Both looser rules are wrong, and each produced a reported bug:
    ///
    /// - Blocking only the rail's exact height left the mid-ramp rails (around
    ///   0.5) matching neither a ground car nor a deck car, so on a measured
    ///   track just 32 of 82 rails stopped anything — the gap cars used to hop
    ///   onto the bridge from the grass.
    /// - Blocking everything at or below the rail meant a deck rail at 1.0 also
    ///   blocked a ground car, walling off the road that passes *underneath* the
    ///   bridge.
    ///
    /// **No tolerance on the top.** A wall's height *is* its top, so a car above it
    /// is over it. A tolerance there gave every wall invisible reach, which made a
    /// ramp's end cap block the legitimate climb: the cap sat at 0.8 but reached
    /// 1.15, and a climber arrives at the mouth at 0.99 (not 1.0 — the per-tick
    /// clamp approaches deck height asymptotically). The floor keeps its tolerance:
    /// that end is about which level the wall belongs to, where a car's size counts.
    public func stops(car: CarState, movedFrom from: Vec2 = .zero) -> Bool {
        switch kind {
        case .boundary:
            return true
        case .gate:
            // One-way level seal: stops what comes from below, and only what
            // comes from the ONE storey below. The gate hangs from its road
            // down to the ground beneath it, not into the earth — a tunnel car
            // a full level further down passes under it exactly like a ground
            // car passes under a deck. No top rule either: a gate isn't a
            // structure with a height a car could clear, it's a threshold
            // ("be of this level, or stay out").
            return car.height < height
                && car.height >= height - Track.levelHeight
        case .embankment:
            // Earth: solid from the storey the ramp STANDS ON up to the road it
            // carries, so a car below cannot drive into a ramp's flank. Above the
            // road there is nothing — a deck crossing over a ramp runs clear.
            //
            // **From its base, not from the ground.** A 2→3 ramp stands on the
            // level-2 deck, so its earth spans 2…3 and the level-1 road passing
            // underneath runs clear. Filling from 0 was indistinguishable with one
            // deck (nothing could be under a ramp) but with three it walled off the
            // road below: reported as a track that built fine and could not be
            // driven, the car stopped dead at h=1.00 on its own asphalt.
            guard car.height <= height + Track.reachTolerance,
                car.height >= base - Track.reachTolerance
            else { return false }
            // **ONE-WAY: you may drive OFF a ramp, never INTO it.** Without this a
            // railless ramp would trap you on it, since the earth that stops the
            // car below is the same segment the car above would leave over.
            //
            // The side test is the car's approach against the wall's stored
            // `outward` — which points away from the road this earth carries, so
            // it is a question about the RAMP, not about this segment's geometry.
            // Two cheaper-looking tests are wrong, both tried: "was the car on
            // road" is true of the legitimate driver too, and the NEAREST wall's
            // outward answers "which side of this segment" on a curve.
            return isApproachedFromOutside(from: from)
        case .rail:
            // **A railing guards the level it edges, and does not reach the
            // floor.** It is a waist-high barrier, not a wall to the ground —
            // the earth beneath a raised road is the embankment's job.
            //
            // The floor used to be `trunc(height)`, which split one bridge edge
            // in two: a rail at 0.999 fenced the ground while its neighbor at
            // 1.0 did not, so the fence had holes and a car pushed out by one
            // could be shoved through another. Rounding to the nearest level
            // fixed that, but broke the MIDDLE of a climb: a rail at 0.52–0.75
            // rounds to level 1 and so demanded `height >= 0.8`, while the car
            // actually driving that stretch of ramp is at 0.52–0.75. Such a rail
            // blocked nobody, which is how a drag along the barrier walked
            // straight out through it — reported as "I can reliably drive through
            // the railing just by dragging the car against the wall".
            //
            // **A railing guards the road it edges, and where that road STARTS
            // depends on whether it climbs** — which is why the wall records it.
            //
            // On a climb the road is at the rail's own height, so protection
            // starts there: rounding to the nearest level instead promoted a rail
            // at 0.52–0.75 to storey 1 and demanded the car be nearly up at 1.0,
            // so it ignored the car actually driving that stretch. A drag along
            // the barrier then walked straight out through it — reported as "I can
            // reliably drive through the railing just by dragging the car against
            // the wall".
            //
            // On the flat the rail belongs to its level even when the deck sags
            // below it (0.96 on an S-curve is a DECK rail), and the ground must
            // pass underneath. Same height, opposite answer — see `Wall.onClimb`.
            let base = onClimb ? height : Double(Track.level(of: height))
            let top = max(height, base) + Track.reachTolerance
            return car.height >= base - Track.reachTolerance && car.height <= top
        }
    }

    /// Whether the car approached from this wall's OUTWARD side — the side its bulk
    /// faces, away from the road it carries.
    ///
    /// Measured from the nearest point ON the segment, not from an endpoint:
    /// `(from - a)` is dominated by the distance to the wall's end rather than by
    /// which side of it the car is on, and a car 600 units away read as outboard.
    ///
    /// A wall with no recorded `outward` has no sides to tell apart, so it stays
    /// symmetric — the honest answer for the map boundary and a level seal, and what
    /// older decoded data becomes.
    func isApproachedFromOutside(from: Vec2) -> Bool {
        guard outward.length > 0.001 else { return true }
        let closest = from.closestPoint(onSegment: a, b)
        return (from - closest).dot(outward) > 0
    }
}
