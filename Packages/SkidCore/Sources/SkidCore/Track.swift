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
    /// Ribbon layer per centerline segment index isn't needed yet (flat
    /// v0.1); the ribbon lives on layer 0.
    public var walls: [Wall]
    /// Ordered checkpoint gates; the last one is the start/finish line.
    public var gates: [Gate]
    public var patches: [SurfacePatch]
    /// Grid slots in start order (pole first), with the heading cars face.
    public var startSlots: [Vec2]
    public var startHeading: Double
    /// World bounds, for the renderer's letterboxing.
    public var size: Vec2

    public init(
        id: String = "",
        centerline: [Vec2],
        width: Double,
        walls: [Wall] = [],
        gates: [Gate] = [],
        patches: [SurfacePatch] = [],
        startSlots: [Vec2] = [],
        startHeading: Double = 0,
        size: Vec2
    ) {
        self.id = id
        self.centerline = centerline
        self.width = width
        self.walls = walls
        self.gates = gates
        self.patches = patches
        self.startSlots = startSlots
        self.startHeading = startHeading
        self.size = size
    }

    /// Distance from `p` to the centerline loop.
    public func distanceToCenterline(_ p: Vec2) -> Double {
        var best = Double.greatestFiniteMagnitude
        for i in centerline.indices {
            let a = centerline[i]
            let b = centerline[(i + 1) % centerline.count]
            best = min(best, p.distance(toSegment: a, b))
        }
        return best
    }

    /// The closest point on the centerline loop to `p`, as (segment index,
    /// parameter along it).
    public func closestCenterlinePoint(to p: Vec2) -> (segment: Int, t: Double) {
        var best = (segment: 0, t: 0.0)
        var bestDistance = Double.greatestFiniteMagnitude
        for i in centerline.indices {
            let a = centerline[i]
            let b = centerline[(i + 1) % centerline.count]
            let closest = p.closestPoint(onSegment: a, b)
            let distance = p.distance(to: closest)
            if distance < bestDistance {
                bestDistance = distance
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
    /// return their first point.
    public func pointAlongCenterline(from p: Vec2, distance: Double) -> Vec2 {
        guard !centerline.isEmpty else { return p }
        let perimeter = centerlineLength
        guard perimeter > 0 else { return centerline[0] }
        var (segment, t) = closestCenterlinePoint(to: p)
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
    /// ribbon; everything beyond the ribbon is grass. The ribbon itself
    /// lives on layer 0 (flat v0.1 content).
    public func surface(at p: Vec2, layer: Int = 0) -> Surface {
        for patch in patches where patch.layer == layer {
            if p.distance(to: patch.center) <= patch.radius {
                return patch.surface
            }
        }
        return layer == 0 && distanceToCenterline(p) <= width / 2 ? .asphalt : .grass
    }
}
