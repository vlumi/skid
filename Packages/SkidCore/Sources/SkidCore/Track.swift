import Foundation

/// A solid barrier segment cars bounce off. Lives on a layer: cars on a
/// different layer pass it freely (bridges/tunnels later).
public struct Wall: Equatable, Sendable, Codable {
    public var a: Vec2
    public var b: Vec2
    public var layer: Int

    public init(from a: Vec2, to b: Vec2, layer: Int = 0) {
        self.a = a
        self.b = b
        self.layer = layer
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
    public var layer: Int

    public init(from a: Vec2, to b: Vec2, forward: Vec2 = .zero, layer: Int = 0) {
        self.a = a
        self.b = b
        self.forward = forward
        self.layer = layer
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

/// A layer transition line across the ribbon: crossing it along `forward`
/// takes the car from `fromLayer` to `toLayer` (driving back down crosses
/// it backward). With `launches`, the forward crossing throws the car —
/// a jump ramp: brief ballistic flight scaled by speed.
public struct Ramp: Equatable, Sendable, Codable {
    public var a: Vec2
    public var b: Vec2
    public var forward: Vec2
    public var fromLayer: Int
    public var toLayer: Int
    public var launches: Bool

    public init(
        from a: Vec2, to b: Vec2, forward: Vec2, fromLayer: Int = 0, toLayer: Int = 1,
        launches: Bool = false
    ) {
        self.a = a
        self.b = b
        self.forward = forward
        self.fromLayer = fromLayer
        self.toLayer = toLayer
        self.launches = launches
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
    public var layer: Int

    public init(center: Vec2, radius: Double, surface: Surface, layer: Int = 0) {
        self.center = center
        self.radius = radius
        self.surface = surface
        self.layer = layer
    }
}

/// The static track: a closed centerline ribbon of asphalt in a field of
/// grass, plus walls, checkpoint gates, patches, and grid slots. Everything
/// carries a layer so crossings never require a data-model refactor; v0.1
/// content stays flat on layer 0.
public struct Track: Equatable, Sendable, Codable {
    /// Stable identity for persistence (hiscores key). "" for ad-hoc
    /// test tracks.
    public var id: String
    /// Closed loop — the last point connects back to the first.
    public var centerline: [Vec2]
    /// Full width of the asphalt ribbon.
    public var width: Double
    /// Centerline segment indexes on the elevated layer (1) — bridges.
    /// Everything else is ground (0).
    public var elevatedSegments: Set<Int>
    /// Ground-layer segments that render as sloped approaches (gradient
    /// wedges climbing to the deck). Purely visual — the car is on the
    /// ground layer until it crosses the ramp line at the deck's edge.
    public var rampSegments: Set<Int>
    /// Layer transition lines (bridge approaches, jump ramps).
    public var ramps: [Ramp]
    public var walls: [Wall]
    /// Ordered checkpoint gates; the last one is the start/finish line.
    public var gates: [Gate]
    public var patches: [SurfacePatch]
    /// Grid slots in start order (pole first), with the heading cars face.
    public var startSlots: [Vec2]
    public var startHeading: Double
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
        elevatedSegments: Set<Int> = [],
        rampSegments: Set<Int> = [],
        ramps: [Ramp] = [],
        walls: [Wall] = [],
        gates: [Gate] = [],
        patches: [SurfacePatch] = [],
        startSlots: [Vec2] = [],
        startHeading: Double = 0,
        size: Vec2,
        pit: Vec2? = nil
    ) {
        self.id = id
        self.centerline = centerline
        self.width = width
        self.elevatedSegments = elevatedSegments
        self.rampSegments = rampSegments
        self.ramps = ramps
        self.walls = walls
        self.gates = gates
        self.patches = patches
        self.startSlots = startSlots
        self.startHeading = startHeading
        self.size = size
        self.pit = pit ?? size * 0.5
    }

    /// Which layer a centerline segment lives on.
    public func segmentLayer(_ index: Int) -> Int {
        elevatedSegments.contains(index) ? 1 : 0
    }

    /// Distance from `p` to the centerline loop — optionally only the
    /// segments of one layer (per-layer ribbon lookups).
    public func distanceToCenterline(_ p: Vec2, layer: Int? = nil) -> Double {
        var best = Double.greatestFiniteMagnitude
        for i in centerline.indices {
            if let layer, segmentLayer(i) != layer { continue }
            let a = centerline[i]
            let b = centerline[(i + 1) % centerline.count]
            best = min(best, p.distance(toSegment: a, b))
        }
        return best
    }

    /// The closest point on the centerline loop to `p`, as (segment index,
    /// parameter along it). `preferLayer` breaks the tie where two layers
    /// overlap in 2D (a bridge crossing): anchor to the car's own layer.
    public func closestCenterlinePoint(
        to p: Vec2, preferLayer: Int? = nil
    ) -> (segment: Int, t: Double) {
        var best = (segment: 0, t: 0.0)
        var bestScore = Double.greatestFiniteMagnitude
        for i in centerline.indices {
            let a = centerline[i]
            let b = centerline[(i + 1) % centerline.count]
            let closest = p.closestPoint(onSegment: a, b)
            var score = p.distance(to: closest)
            if let preferLayer, segmentLayer(i) != preferLayer {
                score += width  // other-layer segments lose ties decisively
            }
            if score < bestScore {
                bestScore = score
                let length = (b - a).length
                let t = length > 0 ? (closest - a).length / length : 0
                best = (i, t)
            }
        }
        return best
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
    /// return their first point. `preferLayer` anchors the start to the
    /// car's own layer where a bridge overlaps the road below; the walk
    /// itself flows over every layer (ramps carry the car up and down).
    public func pointAlongCenterline(
        from p: Vec2, distance: Double, preferLayer: Int? = nil
    ) -> Vec2 {
        guard !centerline.isEmpty else { return p }
        let perimeter = centerlineLength
        guard perimeter > 0 else { return centerline[0] }
        var (segment, t) = closestCenterlinePoint(to: p, preferLayer: preferLayer)
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

    /// Whether `p` lies on a sloped ramp approach. Rendering cares: a car
    /// climbing a ramp is between layers — it draws above the deck (no
    /// popping under the bridge edge) and never gets an occlusion bubble.
    public func isOnRamp(_ p: Vec2) -> Bool {
        for i in rampSegments {
            let a = centerline[i]
            let b = centerline[(i + 1) % centerline.count]
            if p.distance(toSegment: a, b) <= width / 2 + 10 {
                return true
            }
        }
        return false
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
            if distanceToCenterline(gate.a + dir * t) <= width / 2 {
                if first == nil { first = t }
                last = t
            }
        }
        guard let first, let last else { return nil }
        return (gate.a + dir * first, gate.a + dir * last)
    }

    /// What the car at `p` on `layer` is driving on. Patches win over the
    /// ribbon; everything beyond that layer's ribbon is grass.
    public func surface(at p: Vec2, layer: Int = 0) -> Surface {
        for patch in patches where patch.layer == layer {
            if p.distance(to: patch.center) <= patch.radius {
                return patch.surface
            }
        }
        return distanceToCenterline(p, layer: layer) <= width / 2 ? .asphalt : .grass
    }
}
