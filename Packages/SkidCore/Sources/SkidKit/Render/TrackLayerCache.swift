import SkidCore
import SwiftUI

/// **The road never changes during a race — stop redrawing it every frame.**
///
/// The race Canvas rebuilds the whole world 60 times a second, and the road pass
/// is by far its heaviest part: every piece is a shaded ribbon polygon with
/// kerbs, rails, seams and per-segment climb quads, drawn once per storey so
/// bridges layer correctly. On a multi-storey track that measured ~12 ms of a
/// 16.7 ms frame budget in a debug build — reported from the simulator as
/// choppiness on exactly the tracks with bridges.
///
/// This cache renders each storey's road pass ONCE per (track, placement,
/// display scale) into an image, and the frame blits those instead. Only the
/// road is cached: marks, gates and cars stay live, drawn between the cached
/// layers in the same `RenderOrder` slots as before, so "the bridge covers the
/// car under it" still holds. Tracks without a piece layout (ad-hoc test
/// tracks) build nothing and the renderer keeps its live path.
///
/// The build runs behind the ready gate — the race opens frozen on a tap-to-
/// start overlay, so the one-time cost is spent where no frame can hitch.
@MainActor
final class TrackLayerCache {
    private struct Key: Equatable {
        var trackID: String
        var mapRect: CGRect
        var displayScale: CGFloat
    }

    /// Where and how sharply the layers are drawn — one value, because every
    /// storey shares it and the builder needs all of it together.
    private struct Placement {
        var rect: CGRect
        var mapRect: CGRect
        var scale: CGFloat
        var displayScale: CGFloat
    }

    private var key: Key?
    /// One image per storey the track uses, covering `screenRect`.
    private(set) var images: [Int: CGImage] = [:]
    /// Where the images sit on screen: the map rect grown by the drawn
    /// overhang, so widened decks and drop shadows fit inside.
    private(set) var screenRect: CGRect = .zero

    /// Build the layers if (and only if) the track or its placement changed.
    /// Cheap when nothing did — safe to call every frame from the render loop.
    func prepare(track: Track, mapRect: CGRect, displayScale: CGFloat) {
        let newKey = Key(trackID: track.id, mapRect: mapRect, displayScale: displayScale)
        guard key != newKey else { return }
        key = newKey
        images = [:]
        screenRect = .zero
        guard let layout = track.layout, mapRect.width > 0 else { return }
        let scale = mapRect.width / track.size.x
        let overhang = TrackRenderer.drawnOverhang(track: track, scale: scale)
        let placement = Placement(
            rect: mapRect.insetBy(dx: -overhang, dy: -overhang),
            mapRect: mapRect, scale: scale, displayScale: displayScale)
        screenRect = placement.rect
        for storey in TrackRenderer.trackStoreys(track) {
            images[storey] = render(
                layout: layout, track: track, band: TrackRenderer.storeyBand(storey),
                placement: placement)
        }
    }

    /// One storey's road pass, exactly as the live renderer draws it — same
    /// walk, same transform, same `contextScale` (true-screen-point quantities
    /// like the seam overlap must match the live pass, or cached and live
    /// storeys would disagree at their seams).
    private func render(
        layout: TrackLayout, track: Track, band: ClosedRange<Double>, placement: Placement
    ) -> CGImage? {
        var transform = track.layoutTransform
        transform.contextScale = placement.scale
        let rect = placement.rect
        let view = Canvas { context, _ in
            context.translateBy(
                x: placement.mapRect.minX - rect.minX, y: placement.mapRect.minY - rect.minY)
            context.scaleBy(x: placement.scale, y: placement.scale)
            EditorRenderer.drawTrack(
                walk: layout.walk(), width: track.width, gateSeams: [],
                decals: layout.decals, railed: layout.railed,
                roadStyle: layout.roadStyle, transform: transform,
                heightRange: band, into: &context)
        }
        .frame(width: rect.width, height: rect.height)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: rect.width, height: rect.height)
        renderer.scale = placement.displayScale
        renderer.isOpaque = false
        return renderer.cgImage
    }
}
