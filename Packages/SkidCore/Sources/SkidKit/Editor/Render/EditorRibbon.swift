import SkidCore
import SwiftUI

/// **The road's drawn shape** — one piece's two side edges in screen space, split
/// into the runs that actually carry asphalt.
///
/// Split out of `EditorRenderer.swift` on the file-length limit. It is the seam
/// where the piece model becomes geometry, and every drawing pass (surface,
/// shadow, rails) reads it, so it earns its own file.
extension EditorRenderer {
    /// The ribbon geometry both the shadow and the surface pass read.
    struct Ribbon {
        var left: [CGPoint]
        var right: [CGPoint]
        var heights: [Double]
        var samples: [(point: Vec2, height: Double)]
    }

    /// The ribbon's two screen-space side edges plus the per-sample heights.
    /// Half-width scales with the height (a ramp widens as it climbs). The END
    /// normals use the exact PORT heading (entry / exit pose), not the
    /// interpolated sample direction — so adjacent pieces, sharing a port pose,
    /// produce collinear end edges that abut with no grass sliver.
    static func edges(_ placed: PlacedPiece, width: Double, t: Transform) -> Ribbon? {
        // Finer than the default 6°: the kerb's stripes are dashed along this
        // polyline, and coarse vertices give the dash pattern corners to catch
        // on (a visible tilt where a boundary lands on one).
        ribbons(placed, width: width, t: t).first
    }

    /// Every SOLID ribbon of a piece — two for a jump (lip and landing), one for
    /// everything else. The gap carries no geometry, so nothing draws over it.
    static func ribbons(_ placed: PlacedPiece, width: Double, t: Transform) -> [Ribbon] {
        placed.solidRuns(degreesPerSample: 2).compactMap {
            ribbon(placed, samples: $0, width: width, t: t)
        }
    }

    private static func ribbon(
        _ placed: PlacedPiece, samples: [(point: Vec2, height: Double)], width: Double,
        t: Transform
    ) -> Ribbon? {
        guard samples.count >= 2 else { return nil }
        // The port headings belong to the piece's OWN ends — the seams it shares
        // with a neighbor. A gap's cut faces are interior, so they take the
        // interpolated direction like any other sample; using a port heading there
        // would skew the lip's cut to the wrong angle.
        let all = placed.heightedSamples(degreesPerSample: 2)
        let startsAtEntry =
            samples.first.map { first in
                all.first.map { $0.point.distance(to: first.point) < 0.001 } ?? false
            } ?? false
        let endsAtExit =
            samples.last.map { last in
                all.last.map { $0.point.distance(to: last.point) < 0.001 } ?? false
            } ?? false
        let entryDir = Vec2(angle: placed.entry.heading.radians)
        let exitDir = Vec2(angle: placed.exits[0].heading.radians)
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        var heights: [Double] = []
        for (i, s) in samples.enumerated() {
            let dir: Vec2
            if i == 0, startsAtEntry {
                dir = entryDir
            } else if i == samples.count - 1, endsAtExit {
                dir = exitDir
            } else if i == 0 {
                dir = (samples[1].point - s.point).normalized
            } else if i == samples.count - 1 {
                dir = (s.point - samples[i - 1].point).normalized
            } else {
                dir = (samples[i + 1].point - samples[i - 1].point).normalized
            }
            let normal = dir.perpendicular * (width / 2 * Elevation.scale(atHeight: s.height))
            left.append(t.screen(s.point + normal))
            right.append(t.screen(s.point - normal))
            heights.append(s.height)
        }
        return Ribbon(left: left, right: right, heights: heights, samples: samples)
    }
}
