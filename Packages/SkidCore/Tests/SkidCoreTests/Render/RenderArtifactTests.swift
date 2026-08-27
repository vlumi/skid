import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **What the race view actually paints on a banded multi-storey track** —
/// pixel-sampled, because every one of these bugs passed the model-level checks
/// and showed only in the rendered image (reported from device on a knot-shaped
/// track whose climbing loops straddle the storey bands).
@MainActor
final class RenderArtifactTests: XCTestCase {
    /// The reporting track: four climbing loops, fully walled, storeys 0–3.
    static let knot = [
        "AdUBFh96BAQEBAQEAnkEBBACBAQQAgQEEAECAwAIHAMFA0gDSAAIJwABAgME",
        "BQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJgUBBg",
    ].joined()

    #if os(macOS)
    private struct Rendered {
        var image: CGImage
        var mapRect: CGRect
        var scale: Double
        /// Layout-space -> world is a pure translation (see `layoutTransform`).
        var layoutOffset: Vec2

        func luminance(atLayout point: Vec2) -> Double {
            luminance(atWorld: point + layoutOffset)
        }

        /// (green − blue) at a world point: positive on grass, negative on the
        /// navy ground, so "is this the world or the ground" is one sign.
        func greenness(atWorld world: Vec2) -> Double {
            let x = Int(mapRect.minX + world.x * scale)
            let y = Int(mapRect.minY + world.y * scale)
            guard let data = image.dataProvider?.data as Data?,
                x >= 0, y >= 0, x < image.width, y < image.height
            else { return 0 }
            let offset = y * image.bytesPerRow + x * 4
            return (Double(data[offset + 1]) - Double(data[offset + 2])) / 255
        }

        func luminance(atWorld world: Vec2) -> Double {
            let x = Int(mapRect.minX + world.x * scale)
            let y = Int(mapRect.minY + world.y * scale)
            guard let data = image.dataProvider?.data as Data?,
                x >= 0, y >= 0, x < image.width, y < image.height
            else { return -1 }
            let offset = y * image.bytesPerRow + x * 4
            // premultipliedLast: bytes are R, G, B, A. (Reading G, B, A here by
            // accident made every sample bright and the assertions vacuous —
            // caught when a sabotaged renderer still passed.)
            let r = Double(data[offset]) / 255
            let g = Double(data[offset + 1]) / 255
            let b = Double(data[offset + 2]) / 255
            return (r + g + b) / 3
        }
    }

    private func render() throws -> Rendered {
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
        let view = Canvas { context, canvasSize in
            var world = context
            TrackRenderer.draw(scene: scene, into: &world, size: canvasSize)
        }
        .frame(width: size.width, height: size.height)
        .background(Color(red: 0.23, green: 0.5, blue: 0.2))
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        let image = try XCTUnwrap(renderer.cgImage)
        return Rendered(
            image: image, mapRect: mapRect, scale: mapRect.width / track.size.x,
            layoutOffset: track.layoutOffset)
    }

    /// **Grass ends exactly at the world's edge.** The boundary wall used to be
    /// invisible because the lawn ran on to the screen; now the ground beyond
    /// the track's footprint is the menus' navy, so the wall is where the
    /// grass stops. Sampled a few units inside and outside each edge.
    func testGrassEndsAtTheWorldEdge() throws {
        let rendered = try render()
        let size = try PieceCompiler.compile(TrackCode.decode(Self.knot), id: "knot").size
        let inside = rendered.greenness(atWorld: Vec2(6, 6))
        XCTAssertGreaterThan(inside, 0.1, "no grass just inside the world (\(inside))")
        for outside in [Vec2(-8, 6), Vec2(6, -8), Vec2(size.x + 8, 6), Vec2(6, size.y + 8)] {
            let g = rendered.greenness(atWorld: outside)
            XCTAssertLessThan(g, 0, "grass outside the world at \(outside) (\(g))")
        }
    }

    /// **No shadow bar across a lower band's road.** A climbing loop split
    /// across storey bands let the upper fragment's drop shadow spill past its
    /// end cut onto the lower fragment's already-painted road — a hard grey bar
    /// that also crossed the walls (read as gaps in them).
    func testNoShadowBarSpillsOntoALowerBand() throws {
        let rendered = try render()
        // Sampler sanity: grass is mid-green, not near-white — a wrong byte
        // order once made every sample bright and the assertions vacuous.
        let grass = rendered.luminance(atWorld: Vec2(30, 30))
        XCTAssertLessThan(grass, 0.5, "grass sampled \(grass); the sampler is off")
        // Where the reported bar lay: mid-road points along the bottom-right
        // loop's deck, just past the band boundary.
        for world in [Vec2(811, 690), Vec2(760, 690), Vec2(860, 690)] {
            let lum = rendered.luminance(atWorld: world)
            XCTAssertGreaterThan(
                lum, 0.7, "shadow bar at \(world): luminance \(lum)")
        }
    }

    /// **A climb's shade follows its height, not its chord.** One linear
    /// gradient per piece ran along the CHORD, so on a curved ramp the shade
    /// varied ACROSS the road's width (the iso-shade lines are perpendicular to
    /// the chord, not the road) and neighbouring arcs' shading directions
    /// disagreed by the turn angle — a harsh crease on the inside of curved
    /// ramps. Sampled across the width near each curved climb's exit, where the
    /// chord error is largest: with height-following shading the two edges of
    /// one radius match.
    func testACurvedClimbShadesUniformlyAcrossItsWidth() throws {
        let layout = try TrackCode.decode(Self.knot)
        let walk = layout.walk()
        let rendered = try render()
        var worst = 0.0
        var checked = 0
        for piece in walk.placed {
            guard piece.climb != 0, piece.entry.heading != piece.exits[0].heading
            else { continue }
            let samples = piece.heightedSamples(degreesPerSample: 5)
            guard samples.count > 6 else { continue }
            let at = samples.count * 3 / 4
            let along = (samples[at + 1].point - samples[at - 1].point).normalized
            let across = along.perpendicular
            let half =
                Double(PieceCatalog.width) / 2
                * Elevation.scale(atHeight: samples[at].height)
            let inner = rendered.luminance(atLayout: samples[at].point - across * (half * 0.55))
            let outer = rendered.luminance(atLayout: samples[at].point + across * (half * 0.55))
            worst = max(worst, abs(inner - outer))
            checked += 1
        }
        XCTAssertGreaterThan(checked, 4, "the fixture should have curved climbs")
        XCTAssertLessThan(worst, 0.008, "a climb's shade varies across the road")
    }
    #endif
}
