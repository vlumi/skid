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

    public init(
        from a: Vec2, to b: Vec2, height: Double = 0, kind: Kind = .rail,
        outward: Vec2 = .zero
    ) {
        self.a = a
        self.b = b
        self.height = height
        self.kind = kind
        self.outward = outward
    }

}

/// An ordered checkpoint gate across the ribbon — a lap counts only when
/// every gate is crossed in order, in the driving direction.
public struct Gate: Equatable, Sendable, Codable {
    public var a: Vec2
    public var b: Vec2
    /// The driving direction through the gate; a crossing only counts when
    /// the movement has a positive component along it. `.zero` accepts both
    /// directions (undirected gate).
    public var forward: Vec2
    /// The height the gate sits at, so a deck checkpoint isn't crossed by a car
    /// passing underneath it.
    public var height: Double

    public init(from a: Vec2, to b: Vec2, forward: Vec2 = .zero, height: Double = 0) {
        self.a = a
        self.b = b
        self.forward = forward
        self.height = height
    }

    /// Whether a movement from `start` to `end` crosses this gate
    /// (segment–segment intersection; touching an endpoint counts).
    public func isCrossed(movingFrom start: Vec2, to end: Vec2) -> Bool {
        let d1 = (end - start).cross(a - start)
        let d2 = (end - start).cross(b - start)
        let d3 = (b - a).cross(start - a)
        let d4 = (b - a).cross(end - a)
        return d1 * d2 <= 0 && d3 * d4 <= 0 && !(d1 == 0 && d2 == 0)
    }

    /// A crossing that also moves along `forward` — the one that advances
    /// race progress. Driving through backwards never counts.
    public func crossedForward(movingFrom start: Vec2, to end: Vec2) -> Bool {
        guard isCrossed(movingFrom: start, to: end) else { return false }
        guard forward.lengthSquared > 0 else { return true }
        return (end - start).dot(forward) > 0
    }
}

/// A **jump take-off line**: crossing it along `forward` throws the car into a
/// brief ballistic flight scaled by its speed.
///
/// This used to be a layer-transition line, carrying the car between a
/// `fromLayer` and a `toLayer`. Ordinary climbs need no line at all now — the
/// slope is in `Track.heights`, and the car simply follows the road it is on —
/// so all that remains is the launch, which genuinely is an event at a place.
public struct Ramp: Equatable, Sendable, Codable {
    public var a: Vec2
    public var b: Vec2
    public var forward: Vec2

    public init(from a: Vec2, to b: Vec2, forward: Vec2) {
        self.a = a
        self.b = b
        self.forward = forward
    }

    /// -1 = crossed backward, +1 = crossed forward, 0 = not crossed.
    public func crossing(movingFrom start: Vec2, to end: Vec2) -> Int {
        let gate = Gate(from: a, to: b, forward: forward)
        guard gate.isCrossed(movingFrom: start, to: end) else { return 0 }
        return (end - start).dot(forward) > 0 ? 1 : -1
    }
}

/// A patch of non-asphalt surface (mud, water, oil) placed on or off the
/// ribbon. Circles keep the lookup trivially deterministic.
public struct SurfacePatch: Equatable, Sendable, Codable {
    public var center: Vec2
    public var radius: Double
    public var surface: Surface
    /// The height this patch lies at — oil on the deck doesn't affect the road
    /// below.
    public var height: Double

    public init(center: Vec2, radius: Double, surface: Surface, height: Double = 0) {
        self.center = center
        self.radius = radius
        self.surface = surface
        self.height = height
    }
}

/// The static track: a closed centerline ribbon of asphalt in a field of
/// grass, plus walls, checkpoint gates, patches, and grid slots. Everything
/// carries a height, so bridges and (later) tunnels need no data-model
/// refactor; a flat track is all zeros.
public struct Track: Equatable, Sendable, Codable {
    /// Stable identity for persistence (hiscores key). "" for ad-hoc
    /// test tracks.
    public var id: String
    /// Closed loop — the last point connects back to the first.
    public var centerline: [Vec2]
    /// Full width of the asphalt ribbon **at ground level**. The ribbon gets
    /// wider with height — see `halfWidth(atHeight:)`, which is what anything
    /// asking "is this on the road" must use.
    public var width: Double
    /// **Height per centerline point**, 0 = ground, 1 = bridge deck, varying
    /// continuously across a ramp — the single source of truth for elevation.
    ///
    /// This replaced a pair of discrete layer sets (`elevatedSegments` +
    /// `rampSegments`) and a per-car integer `layer`. The discrete model had to
    /// flip a car between layers at a line, which produced a family of bugs that
    /// were awkward to patch and impossible to fully close: the car popping as it
    /// crossed, the road vanishing from under it mid-transition, and a car
    /// driving under a bridge coming out on top of the ramp. With a height per
    /// point, "which surface am I on" is a comparison instead of a state
    /// machine, and the editor's continuous look is exactly what the sim uses.
    ///
    /// Parallel to `centerline`; a track with no elevation is all zeros.
    public var heights: [Double]

    /// **The top of the piece each centerline point belongs to** — the highest
    /// end of the piece that emitted it, parallel to `centerline`. The renderer
    /// paints each ribbon piece WHOLE at the storey of this value, so anything
    /// that must stack with the ribbon (a car mid-climb) has to stack by the
    /// same value: a car at height 0.36 is at level 0, but the ramp under it
    /// painted a level up, and stacking the car by raw height slid it beneath
    /// the upper half of its own road.
    public var deckTops: [Double]
    /// Jump take-off lines. A plain ramp needs no line at all now — the climb is
    /// in `heights` — but a launch still needs a moment where the car leaves the
    /// road ballistically.
    public var ramps: [Ramp]
    public var walls: [Wall]
    /// Ordered checkpoint gates; the last one is the start/finish line.
    public var gates: [Gate]
    public var patches: [SurfacePatch]
    /// The piece layout this track was compiled from.
    ///
    /// Kept so the race view can draw the track with **the editor's renderer**,
    /// off the same placed pieces the editor draws — which is the only way the
    /// two can be identical rather than merely similar. Two independent
    /// renderers over two different inputs drifted apart in kerbs, rails and
    /// ramp markings, and every fix had to be made twice.
    public var layout: TrackLayout?
    /// How far the compiled geometry was moved from where walking `layout`
    /// puts it, so anything drawn from the layout can be shifted to match.
    ///
    /// Compiling re-frames a track onto its own footprint (see
    /// `PieceCompiler.framed`), and that offset isn't a whole number of units, so
    /// it can't be folded back into the layout's exact integer origin. Drawing
    /// the raw walk therefore put the track visibly off from where it physically
    /// was — right shape, wrong place.
    public var layoutOffset: Vec2
    /// Grid slots in start order (pole first), with the heading cars face.
    public var startSlots: [Vec2]
    public var startHeading: Double
    /// The height the grid sits at — the layout's baseline, so cars spawn ON the
    /// road when a whole track is raised rather than under it.
    public var startHeight: Double
    /// World bounds, for the renderer's letterboxing.
    public var size: Vec2
    /// The "pit": an authored infield point, clear of the racing line, that
    /// holds off-track chrome (today just the pause button, so it never lands
    /// on the ribbon). One per track, placed by hand near start/finish.
    /// Defaults to the world center for ad-hoc tracks that don't set one.
    public var pit: Vec2

    public init(
        id: String = "",
        centerline: [Vec2],
        width: Double,
        heights: [Double]? = nil,
        deckTops: [Double]? = nil,
        ramps: [Ramp] = [],
        walls: [Wall] = [],
        gates: [Gate] = [],
        patches: [SurfacePatch] = [],
        layout: TrackLayout? = nil,
        layoutOffset: Vec2 = .zero,
        startSlots: [Vec2] = [],
        startHeading: Double = 0,
        startHeight: Double = 0,
        size: Vec2,
        pit: Vec2? = nil
    ) {
        self.id = id
        self.centerline = centerline
        self.width = width
        // A flat track needs no height data at all, so `nil` means all-ground.
        self.heights = heights ?? Array(repeating: 0, count: centerline.count)
        // Ad-hoc tracks (built without the piece compiler) have no pieces, so
        // each point's "deck top" is honestly its own height.
        self.deckTops = deckTops ?? self.heights
        self.ramps = ramps
        self.walls = walls
        self.gates = gates
        self.patches = patches
        self.layout = layout
        self.layoutOffset = layoutOffset
        self.startSlots = startSlots
        self.startHeading = startHeading
        self.startHeight = startHeight
        self.size = size
        self.pit = pit ?? size * 0.5
    }

    /// The height of a centerline point (0 = ground, 1 = deck).
    public func height(ofPoint index: Int) -> Double {
        guard heights.indices.contains(index) else { return 0 }
        return heights[index]
    }

    /// The height of a segment: the mean of its two endpoints, so a ramp segment
    /// reports the middle of its own climb.
    public func height(ofSegment index: Int) -> Double {
        guard !centerline.isEmpty else { return 0 }
        let next = (index + 1) % centerline.count
        return (height(ofPoint: index) + height(ofPoint: next)) / 2
    }

    /// Whether a segment is drivable by a car at `height`.
    ///
    /// This is the whole of the old layer system, reduced to a comparison. A ramp
    /// needs no special case: its own height runs continuously from 0 to 1, so a
    /// car climbing it matches the part it is on and no other. That is what makes
    /// "drive under the bridge and pop out on top of the ramp" impossible rather
    /// than merely guarded against — the car under the bridge is at height 0, the
    /// deck above it is at 1, and no comparison can confuse them.
    public func segment(
        _ index: Int, isAt height: Double, tolerance: Double = Self.surfaceTolerance
    ) -> Bool {
        abs(self.height(ofSegment: index) - height) <= tolerance
    }

    /// Total length of the centerline loop.
    public var centerlineLength: Double {
        var total = 0.0
        for i in centerline.indices {
            total += centerline[i].distance(to: centerline[(i + 1) % centerline.count])
        }
        return total
    }

    /// Walk `distance` units forward along the centerline loop, starting
    /// from the point nearest `p` — the AI's lookahead target. Distances
    /// beyond a full loop wrap; zero-length segments (arc/straight joints
    /// share endpoints) are skipped. Degenerate loops (no length at all)
    /// return their first point. `preferHeight` anchors the start to the car's
    /// own height where a bridge overlaps the road below; the walk itself flows
    /// over every height (a ramp carries the car up and down).
    public func pointAlongCenterline(
        from p: Vec2, distance: Double, preferHeight: Double? = nil
    ) -> Vec2 {
        guard !centerline.isEmpty else { return p }
        let perimeter = centerlineLength
        guard perimeter > 0 else { return centerline[0] }
        var (segment, t) = closestCenterlinePoint(to: p, preferHeight: preferHeight)
        var remaining = distance.truncatingRemainder(dividingBy: perimeter)
        for _ in 0..<(centerline.count * 2 + 2) {
            let a = centerline[segment]
            let b = centerline[(segment + 1) % centerline.count]
            let length = (b - a).length
            if length > 0 {
                let left = length * (1 - t)
                if remaining <= left {
                    return a + (b - a) * min(1, t + remaining / length)
                }
                remaining -= left
            }
            segment = (segment + 1) % centerline.count
            t = 0
        }
        // Defensive only: `remaining < perimeter` guarantees an in-loop
        // return; degenerate loops exited at the guard above.
        return centerline[segment]
    }

    /// Whether the road at `p` is sloped rather than level — a ramp. Used for
    /// rendering (a climbing car draws above the deck so its nose never slides
    /// under the bridge edge) and for the never-invisible bubble rule.
    ///
    /// Derived from `heights` rather than a stored set: a segment is sloped when
    /// its two ends sit at different heights.
    /// `height` is the car's own height, and it matters: without it this answers
    /// "is there sloped road near this spot", which is true for a car sitting on
    /// the grass beside a ramp and for one on the road passing *under* one. The
    /// renderer used that to decide a car was on a ramp and drew it up on the
    /// bridge while the sim had it on the grass at height 0 — visible in the debug
    /// overlay as a car reading "h 0.00 / grass / off road" while drawn on the deck.
    public func isOnRamp(_ p: Vec2, height: Double? = nil, near tolerance: Double = 10) -> Bool {
        for i in centerline.indices {
            let next = (i + 1) % centerline.count
            let low = self.height(ofPoint: i)
            let high = self.height(ofPoint: next)
            guard abs(low - high) > 0.001 else { continue }
            let reach = halfWidth(atHeight: max(low, high)) + tolerance
            guard p.distance(toSegment: centerline[i], centerline[next]) <= reach
            else { continue }
            // The car must be at roughly the height of THIS piece of slope.
            guard let height else { return true }
            let span = min(low, high)...max(low, high)
            if height >= span.lowerBound - Self.surfaceTolerance,
                height <= span.upperBound + Self.surfaceTolerance
            {
                return true
            }
        }
        return false
    }

    /// The road's **height** at `p` (0 = ground, 1 = deck), interpolated along
    /// whichever stretch of road the point sits on.
    ///
    /// `preferHeight` disambiguates a bridge crossing, where two stretches share
    /// the same 2D position — pass the car's own height and it stays on its own
    /// road. This is now a plain interpolation of stored data; it used to
    /// reconstruct the climb by guessing which end of a ramp was the deck.
    public func height(at p: Vec2, preferHeight: Double? = nil) -> Double {
        guard !centerline.isEmpty else { return 0 }
        let (segment, t) = closestCenterlinePoint(to: p, preferHeight: preferHeight)
        let next = (segment + 1) % centerline.count
        let from = height(ofPoint: segment)
        let to = height(ofPoint: next)
        return from + (to - from) * t
    }

    /// The top of the piece of road at `p` — the height the renderer bins that
    /// piece's whole ribbon by. `preferHeight` anchors a bridge crossing to the
    /// car's own stretch, exactly as in `height(at:)`.
    public func deckTop(at p: Vec2, preferHeight: Double? = nil) -> Double {
        guard deckTops.count == centerline.count, !deckTops.isEmpty else {
            return height(at: p, preferHeight: preferHeight)
        }
        let (segment, _) = closestCenterlinePoint(to: p, preferHeight: preferHeight)
        // Every segment belongs WHOLLY to the piece of its end point: the
        // compiler emits each piece's points after its entry through its exit,
        // so a segment never spans two pieces. Attributing by the end point is
        // therefore exact — the nearer-endpoint guess it replaces over-reached
        // by half a segment, which on a sparsely-sampled straight extended a
        // ramp's storey up to 60 units into the flat run beyond it.
        return deckTops[(segment + 1) % deckTops.count]
    }

    /// The portion of a gate that lies on the asphalt ribbon — where a
    /// checkpoint line paints on the road. The gate itself is wider (it
    /// spans the whole corridor); this is only its visible part. nil if the
    /// gate never touches the ribbon.
    public func ribbonSpan(of gate: Gate, samples: Int = 64) -> (a: Vec2, b: Vec2)? {
        let dir = gate.b - gate.a
        var first: Double?
        var last: Double?
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            if distanceToCenterline(gate.a + dir * t) <= halfWidth(atHeight: gate.height) {
                if first == nil { first = t }
                last = t
            }
        }
        guard let first, let last else { return nil }
        return (gate.a + dir * first, gate.a + dir * last)
    }

    /// What a car at `p` and `height` is driving on. Patches win over the
    /// ribbon; everything beyond the road at that height is grass.
    public func surface(at p: Vec2, height: Double = 0) -> Surface {
        for patch in patches where abs(patch.height - height) <= Self.surfaceTolerance {
            if p.distance(to: patch.center) <= patch.radius {
                return patch.surface
            }
        }
        return distanceToCenterline(p, height: height) <= halfWidth(atHeight: height)
            ? .asphalt : .grass
    }
}
