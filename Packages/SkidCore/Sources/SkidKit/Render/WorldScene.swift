import SkidCore
import SwiftUI

/// Everything one frame of the world needs, as plain values (the Canvas
/// renderer closure is not MainActor, so it gets copies, not the session).
struct WorldScene {
    var race: Race
    var marks: MarkStore
    var gateSpans: [(a: Vec2, b: Vec2)?]
    var colors: [Color]
    /// Where the map is placed on screen (the allocator's result). The
    /// bands + pause key off the same rect, so the map is drawn exactly
    /// where the layout expects it.
    var mapRect: CGRect
    /// PB-ghost cars to draw translucently (time trial), if any.
    var ghosts: [CarState] = []
    /// Pre-rendered road layers by storey (see `TrackLayerCache`) — plain
    /// values, not the cache itself, because the Canvas renderer closure that
    /// reads the scene is not MainActor. Empty means draw the road live.
    var roadLayers: [Int: CGImage] = [:]
    /// The screen rect `roadLayers` covers (the map rect plus drawn overhang).
    var roadLayersRect: CGRect = .zero
    /// Draw the sim's own view of the world on top (see `DebugOverlay`).
    var debug = false
}

extension Track {
    /// The transform that puts layout-space drawing where the compiled geometry
    /// actually is. The race context is already scaled to world units, so this is
    /// a pure translation by `layoutOffset`.
    var layoutTransform: EditorRenderer.Transform {
        EditorRenderer.Transform(
            scale: 1, offset: CGSize(width: layoutOffset.x, height: layoutOffset.y))
    }
}
