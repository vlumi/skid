import SkidCore
import SwiftUI

extension EditorRenderer {
    /// All ground edge decoration for the layout, laid down BEFORE any asphalt.
    ///
    /// Drawing it first *is* the clipping rule: a kerb can never cover a
    /// neighboring piece's road, because that road is painted afterwards; and
    /// two overlapping kerb bands merge into one instead of fighting over the
    /// same strip. Deck edges are excluded — those are guard rails, real
    /// barriers, drawn on top of the surface instead.
    ///
    /// Samples are gathered for the whole ring per side, so a kerb that spans
    /// several pieces is one continuous run with one stripe rhythm. Distances
    /// are accumulated in WORLD units so stripe length never depends on zoom.
    static func drawAllEdges(
        walk: WalkResult, kerbs: KerbPlan, width: Double, t: Transform,
        heightRange: ClosedRange<Double> = -1...2,
        into context: inout GraphicsContext
    ) {
        let stripeLength = width * 0.22
        for side in [true, false] {
            for run in edgeRuns(
                walk: walk, kerbs: kerbs, width: width, side: side,
                within: (t, heightRange))
            {
                EdgeDecoration.draw(
                    run: run.samples, style: run.style,
                    band: bandWidth(run.style, t: t), stripeLength: stripeLength,
                    into: &context)
            }
        }
    }

    /// How wide the decoration shows. Drawn straddling the road edge, so the
    /// stroke is twice the visible width — the asphalt pass covers the inner
    /// half, leaving exactly `edgeLine` / `kerbBand` of paint outboard.
    private static func bandWidth(_ style: KerbPlan.Edge, t: Transform) -> CGFloat {
        switch style {
        case .line: return max(1.5, Double(PieceCatalog.edgeLine) * 2 * t.scale)
        case .kerb: return max(3, Double(PieceCatalog.kerbBand) * 2 * t.scale)
        }
    }

    /// One continuous stretch of a single style along one side of the ring.
    struct EdgeRun {
        var style: KerbPlan.Edge
        var samples: [EdgeDecoration.Sample]
    }

    /// Break one side of the ring into runs of a single style, gathering samples
    /// across piece boundaries so a run is never cut short by a joint.
    private static func edgeRuns(
        walk: WalkResult, kerbs: KerbPlan, width: Double, side: Bool,
        within: (t: Transform, heightRange: ClosedRange<Double>)
    ) -> [EdgeRun] {
        let t = within.t
        let heightRange = within.heightRange
        var runs: [EdgeRun] = []
        var current: EdgeRun?
        var distance = 0.0
        var previousWorld: Vec2?

        func close() {
            if let run = current, run.samples.count >= 2 { runs.append(run) }
            current = nil
            // Each run measures distance from ITS own start, so the stripe
            // rhythm restarts cleanly at a style change.
            distance = 0
        }

        for (index, placed) in walk.placed.enumerated() {
            // Deck edges get guard rails instead, and break any run in progress.
            // A piece outside the requested height band breaks it too.
            guard !Track.isOffGround(placed.entryHeight), !Track.isOffGround(placed.exitHeight),
                heightRange.contains(max(placed.entryHeight, placed.exitHeight))
            else {
                close()
                continue
            }
            let geometry = edgeGeometry(placed, width: width, side: side)
            for (sample, point) in geometry.enumerated() {
                let style = style(kerbs, piece: index, sample: sample, side: side)
                // Skip the joint sample a piece shares with its predecessor:
                // both pieces carry it, and a repeat is a zero-length step.
                if let previous = previousWorld, (point.world - previous).length < 0.01 {
                    continue
                }
                if style != current?.style {
                    // Carry the boundary point into the next run so runs abut
                    // exactly, with no sliver of background between them. It
                    // starts the new run's distance at zero.
                    let boundary = current?.samples.last
                    close()
                    current = EdgeRun(style: style, samples: [])
                    if let boundary {
                        current?.samples.append(
                            EdgeDecoration.Sample(
                                point: boundary.point, normal: boundary.normal, distance: 0))
                    }
                } else if let previous = previousWorld {
                    distance += (point.world - previous).length
                }
                previousWorld = point.world
                current?.samples.append(
                    EdgeDecoration.Sample(
                        point: t.screen(point.world), normal: point.normal, distance: distance))
            }
        }
        close()
        return runs
    }

    private static func style(
        _ kerbs: KerbPlan, piece: Int, sample: Int, side: Bool
    ) -> KerbPlan.Edge {
        let pair = kerbs.style(piece: piece, sample: sample)
        return side ? pair.left : pair.right
    }

    /// One side's edge points in WORLD space, each with its outward normal.
    /// World space matters: distances along the run are measured here, so the
    /// stripe rhythm is a property of the track rather than of the viewport.
    private static func edgeGeometry(
        _ placed: PlacedPiece, width: Double, side: Bool
    ) -> [(world: Vec2, normal: CGPoint)] {
        let samples = placed.heightedSamples(degreesPerSample: KerbPlan.degreesPerSample)
        guard samples.count >= 2 else { return [] }
        let entryDir = Vec2(angle: placed.entry.heading.radians)
        let exitDir = Vec2(angle: placed.exits[0].heading.radians)
        return samples.indices.map { index in
            let direction: Vec2
            if index == 0 {
                direction = entryDir
            } else if index == samples.count - 1 {
                direction = exitDir
            } else {
                direction = (samples[index + 1].point - samples[index - 1].point).normalized
            }
            // The renderer's "left" is `dir.perpendicular`; the outward normal on
            // that side points the same way, and the opposite way on the other.
            let outward =
                side
                ? direction.perpendicular
                : Vec2(-direction.perpendicular.x, -direction.perpendicular.y)
            let half = width / 2 * Elevation.scale(atHeight: samples[index].height)
            return (samples[index].point + outward * half, CGPoint(x: outward.x, y: outward.y))
        }
    }
}
