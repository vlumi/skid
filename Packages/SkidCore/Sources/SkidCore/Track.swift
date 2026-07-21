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
/// every gate is crossed in order (lap logic itself lands with race
/// structure; the data and crossing test live here from day one).
public struct Gate: Equatable, Sendable, Codable {
    public var a: Vec2
    public var b: Vec2
    public var layer: Int

    public init(from a: Vec2, to b: Vec2, layer: Int = 0) {
        self.a = a
        self.b = b
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
        centerline: [Vec2],
        width: Double,
        walls: [Wall] = [],
        gates: [Gate] = [],
        patches: [SurfacePatch] = [],
        startSlots: [Vec2] = [],
        startHeading: Double = 0,
        size: Vec2
    ) {
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
