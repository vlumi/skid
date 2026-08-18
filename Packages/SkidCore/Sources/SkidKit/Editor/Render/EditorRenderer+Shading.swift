import SkidCore
import SwiftUI

/// The road surface's shading — split from `EditorRenderer.swift` on the
/// file-length budget: how a piece's asphalt is filled, and the height-to-shade
/// rule everything else keys off.
extension EditorRenderer {
    private static let deckGray = Color(white: 0.72)

    /// Fill the road surface: flat pieces solid (deck lighter), a ramp shaded
    /// dark(ground)→light(deck) so the slope reads.
    ///
    /// **A climb shades along the ROAD, segment by segment** — not with one
    /// linear gradient from entry to exit. On a curved ramp that gradient runs
    /// along the CHORD, so the shade varied across the road's width and two
    /// neighbouring arcs disagreed everywhere but the centerline — reported from
    /// device as a harsh jump in luminosity on the inside of curved ramps. Each
    /// sample segment now takes the shade of its own height, which is radially
    /// uniform and continuous across seams by construction. The base fill in the
    /// mid shade sits under the segments so their antialiased joints can never
    /// show background.
    static func fillRoad(
        _ outline: Path, placed: PlacedPiece, ribbon: Ribbon, t: Transform,
        into context: inout GraphicsContext
    ) {
        let edges = (left: ribbon.left, right: ribbon.right)
        let samples = ribbon.samples
        // Shade follows HEIGHT, at both ends of every piece — not a binary
        // ground/deck pick from the entry. A half-climb blends from its entry
        // shade to its exit shade, and a road resting at 0.5 takes the matching
        // mid shade, so a split climb reads as one continuous surface instead
        // of banding at each seam.
        // The 1-point pre-stroke closes the antialiased sliver between the rail's
        // inner edge and the fill's outer edge — invisible on the ground, but an
        // elevated piece has its dark drop shadow directly behind that sliver,
        // which read as a hairline gap along both edges of every raised curve.
        let seal = max(1.0, 1.5 / t.contextScale)
        guard placed.climb != 0 else {
            let shade = roadShade(at: placed.entryHeight)
            context.stroke(outline, with: .color(shade), lineWidth: seal)
            context.fill(outline, with: .color(shade))
            return
        }
        // The base coat under the segment quads: entry->exit gradient, NOT the
        // mid shade — it only ever shows as the 1pt seal at the edges and the
        // seam overhangs, and a mid-shade overhang past the cut differed from
        // the neighbour's local shade by half the climb (reported as aliasing
        // lines at ramp seams). Along the chord is exact AT the cuts, which is
        // the only place this coat peeks out lengthwise.
        let coat = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [
                roadShade(at: placed.entryHeight), roadShade(at: placed.exitHeight),
            ]),
            startPoint: edges.left.first ?? .zero,
            endPoint: edges.left.last ?? .zero)
        context.stroke(outline, with: coat, lineWidth: seal)
        context.fill(outline, with: coat)
        let count = min(edges.left.count, edges.right.count, samples.count)
        guard count > 1 else { return }
        // The run's first and last quads reach past their cuts (the same
        // seamOverlap the ribbon fill uses): flush quads left a thin line of the
        // base fill's mid shade showing at every piece seam of a climb.
        let overlap = seamOverlap / t.contextScale
        let left = extendEnds(Array(edges.left.prefix(count)), by: overlap)
        let right = extendEnds(Array(edges.right.prefix(count)), by: overlap)
        for index in 0..<(count - 1) {
            var quad = Path()
            quad.addLines([
                left[index], left[index + 1],
                right[index + 1], right[index],
            ])
            quad.closeSubpath()
            let height = (samples[index].height + samples[index + 1].height) / 2
            context.fill(quad, with: .color(roadShade(at: height)))
        }
    }

    /// Ground asphalt at the bottom storey, lightest at the top one, blended
    /// between — so height reads as brightness at EVERY level.
    ///
    /// This used to divide by `levelHeight` and clamp at 1, which meant the shade
    /// topped out at the first deck: with three storeys, heights 1, 2 and 3 were
    /// all the same gray and the only cue left was the car's size. Spanning the
    /// world's actual range keeps each storey distinguishable however many there
    /// are, and is unchanged for a two-level track (0…1 spans the same 0…1).
    private static func roadShade(at height: Double) -> Color {
        Color(white: roadShadeWhite(at: height))
    }

    /// The shade's white value, exposed so a test can assert the storeys are
    /// distinguishable without reading pixels.
    static func roadShadeWhite(at height: Double) -> Double {
        let span = Double(Track.highestLevel - Track.lowestLevel) * Track.levelHeight
        let above = height - Double(Track.lowestLevel) * Track.levelHeight
        let f = span > 0 ? min(1, max(0, above / span)) : 0
        // The spread is 0.10 per LEVEL rather than across the whole world, so
        // adding storeys keeps each one as distinguishable as ground-vs-deck was
        // instead of dividing one narrow band ever more finely (three storeys
        // would have been 0.033 apart, which reads as one gray).
        let levels = max(1.0, span / Track.levelHeight)
        return 0.62 + 0.10 * levels * f
    }

    /// The brightest a road gets, so callers that need the range agree with the
    /// shading rather than guessing it.
    static var roadShadeCeiling: Double {
        let levels = max(
            1.0,
            Double(Track.highestLevel - Track.lowestLevel))
        return 0.62 + 0.10 * levels
    }
}
