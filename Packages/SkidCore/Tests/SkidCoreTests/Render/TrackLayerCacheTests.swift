import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The cached road must be the SAME picture the live pass paints.** The race
/// blits pre-rendered storey images instead of re-shading every ribbon each
/// frame (`TrackLayerCache`); these tests pin that the blit lands on the same
/// pixels — same rect, same scale, same seams — by rendering the reporting
/// 4-storey track both ways and comparing. A wrong offset or a stale rect
/// would pass every model-level check and show only here.
@MainActor
final class TrackLayerCacheTests: XCTestCase {
    /// The same 4-storey knot the render-artifact tests use: climbing loops,
    /// fully walled, bridges over roads — every layering case at once.
    static let knot = [
        "AdUBFh96BAQEBAQEAnkEBBACBAQQAgQEEAECAwAIHAMFA0gDSAAIJwABAgME",
        "BQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJgUBBg",
    ].joined()

    #if os(macOS)
    private struct Fixture {
        var scene: WorldScene
        var track: Track
        var size: CGSize
    }

    private func makeFixture() throws -> Fixture {
        let layout = try TrackCode.decode(Self.knot)
        let track = try PieceCompiler.compile(layout, id: "knot")
        let size = CGSize(width: 750, height: 1000)
        let mapRect = TrackRenderer.fittedMapRect(trackSize: track.size, in: size)
        let race = Race(
            track: track, players: [PlayerID(0)],
            config: RaceConfig(laps: 3, countdownTicks: 120))
        let scene = WorldScene(
            race: race, marks: MarkStore(), gateSpans: [], colors: [.blue],
            mapRect: mapRect)
        return Fixture(scene: scene, track: track, size: size)
    }

    private func render(scene: WorldScene, size: CGSize) throws -> CGImage {
        let view = Canvas { context, canvasSize in
            var world = context
            TrackRenderer.draw(scene: scene, into: &world, size: canvasSize)
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        return try XCTUnwrap(renderer.cgImage)
    }

    private func luminance(_ image: CGImage, _ x: Int, _ y: Int) -> Double {
        guard let data = image.dataProvider?.data as Data? else { return -1 }
        let offset = y * image.bytesPerRow + x * 4
        let r = Double(data[offset]) / 255
        let g = Double(data[offset + 1]) / 255
        let b = Double(data[offset + 2]) / 255
        return (r + g + b) / 3
    }

    /// Render the whole scene live, then again with the cached layers, and
    /// compare a dense grid of pixels. Antialiasing at a resampled edge may
    /// wobble a pixel here and there; a wrong blit rect or a missing storey
    /// moves whole regions, which is what the mismatch budget catches.
    func testCachedLayersPaintTheSamePictureAsTheLivePass() throws {
        let fixture = try makeFixture()
        let scene = fixture.scene
        let size = fixture.size
        let track = fixture.track
        let live = try render(scene: scene, size: size)

        let cache = TrackLayerCache()
        cache.prepare(track: track, mapRect: scene.mapRect, displayScale: 1)
        XCTAssertEqual(
            Set(cache.images.keys), Set(TrackRenderer.trackStoreys(track)),
            "every storey the track uses must have a cached layer")
        var cached = scene
        cached.roadLayers = cache.images
        cached.roadLayersRect = cache.screenRect
        let blitted = try render(scene: cached, size: size)

        var mismatches = 0
        var samples = 0
        for y in stride(from: 0, to: Int(size.height), by: 4) {
            for x in stride(from: 0, to: Int(size.width), by: 4) {
                samples += 1
                if abs(luminance(live, x, y) - luminance(blitted, x, y)) > 0.1 {
                    mismatches += 1
                }
            }
        }
        XCTAssertLessThan(
            Double(mismatches) / Double(samples), 0.002,
            "cached render differs from live at \(mismatches)/\(samples) samples")
    }

    /// Preparing again with the same key must not rebuild — the whole point is
    /// that the per-frame call is free. A changed placement must rebuild.
    func testTheCacheRebuildsOnlyWhenTheKeyChanges() throws {
        let fixture = try makeFixture()
        let track = fixture.track
        let scene = fixture.scene
        let cache = TrackLayerCache()
        cache.prepare(track: track, mapRect: scene.mapRect, displayScale: 1)
        let first = try XCTUnwrap(cache.images[0])
        cache.prepare(track: track, mapRect: scene.mapRect, displayScale: 1)
        XCTAssertTrue(cache.images[0] === first, "an unchanged key must not rebuild")
        cache.prepare(
            track: track, mapRect: scene.mapRect.offsetBy(dx: 10, dy: 0), displayScale: 1)
        XCTAssertFalse(cache.images[0] === first, "a moved map must rebuild the layers")
    }

    /// A track without a piece layout (ad-hoc test tracks) builds nothing, and
    /// the renderer keeps its live centerline path.
    func testAnAdHocTrackBuildsNoLayers() {
        let track = Track(
            centerline: [Vec2(0, -400), Vec2(0, 400)],
            width: 120, size: Vec2(2_000, 2_000))
        let cache = TrackLayerCache()
        cache.prepare(
            track: track, mapRect: CGRect(x: 0, y: 0, width: 300, height: 300),
            displayScale: 1)
        XCTAssertTrue(cache.images.isEmpty)
    }
    #endif
}
