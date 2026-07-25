import SkidCore
import SwiftUI

/// Draws the decoration along a track's road edges: a thin white line
/// everywhere, and a red/white striped kerb where a corner earns one.
///
/// **Why this is its own thing, built like the road rather than stroked.**
/// A kerb is a *ribbon* running along the edge — the same kind of object as the
/// asphalt itself — so it's built the same way: walk the edge, and for every
/// step emit a quad with its own two end normals. Every stripe boundary is then
/// radial by construction, and stripe length is chosen in world units, so
/// nothing about the result depends on zoom or on how finely the geometry
/// happened to be sampled.
///
/// Earlier attempts stroked a dashed line along the edge. That fails three ways
/// at once, and no amount of tuning fixes any of them: a dash is cut
/// perpendicular to the local chord (so boundaries tilt off the radius), the
/// pattern is measured in screen space (so it re-phases on zoom, making the
/// tilts flicker), and a run's dash count depends on its length (so abutting
/// runs disagree at joints).
enum EdgeDecoration {
    static let white = Color(white: 0.95)
    static let red = Color(red: 0.82, green: 0.16, blue: 0.14)

    /// One sample along a road edge: where it is, and which way is outward.
    struct Sample {
        var point: CGPoint
        /// Unit outward normal — the direction decoration extends.
        var normal: CGPoint
        /// Distance along the edge from the run's start, in WORLD units, so
        /// stripe length can be decided independently of screen scale.
        var distance: Double
    }

    /// Draw one continuous run of edge decoration.
    ///
    /// `samples` must be dense enough to follow the curve; the run is subdivided
    /// into stripes of `stripeLength` world units, rounded to a whole number so
    /// the run starts and ends on a complete stripe.
    static func draw(
        run samples: [Sample], style: KerbPlan.Edge, band: CGFloat, stripeLength: Double,
        into context: inout GraphicsContext
    ) {
        guard samples.count >= 2, band > 0 else { return }
        switch style {
        case .line:
            // A plain line is one unbroken band.
            context.fill(quad(samples, band: band), with: .color(white))
        case .kerb:
            let total = samples[samples.count - 1].distance
            guard total > 0 else { return }
            // An ODD stripe count, so a run reads red-at-both-ends rather than
            // petering out on white (which looks like the kerb was cut short).
            var stripes = max(3, Int((total / stripeLength).rounded()))
            if stripes.isMultiple(of: 2) { stripes += 1 }
            let step = total / Double(stripes)
            for stripe in 0..<stripes {
                let from = Double(stripe) * step
                let through = Double(stripe + 1) * step
                let span = slice(samples, from: from, to: through)
                guard span.count >= 2 else { continue }
                context.fill(
                    quad(span, band: band),
                    with: .color(stripe.isMultiple(of: 2) ? red : white))
            }
        }
    }

    /// The band covering these samples: out along every normal, then back.
    private static func quad(_ samples: [Sample], band: CGFloat) -> Path {
        var path = Path()
        let half = band / 2
        for (index, sample) in samples.enumerated() {
            let point = offset(sample, by: half)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        for sample in samples.reversed() {
            path.addLine(to: offset(sample, by: -half))
        }
        path.closeSubpath()
        return path
    }

    private static func offset(_ sample: Sample, by distance: CGFloat) -> CGPoint {
        CGPoint(
            x: sample.point.x + sample.normal.x * distance,
            y: sample.point.y + sample.normal.y * distance)
    }

    /// The samples covering [`from`, `to`] along the run, with interpolated
    /// samples at both ends so a stripe boundary lands exactly on the requested
    /// distance rather than snapping to whichever sample is nearest.
    private static func slice(_ samples: [Sample], from: Double, to: Double) -> [Sample] {
        var span: [Sample] = []
        if let start = interpolated(samples, at: from) { span.append(start) }
        for sample in samples where sample.distance > from && sample.distance < to {
            span.append(sample)
        }
        if let end = interpolated(samples, at: to) { span.append(end) }
        return span
    }

    /// A sample at an exact distance along the run, blended from its neighbors.
    private static func interpolated(_ samples: [Sample], at distance: Double) -> Sample? {
        guard let last = samples.last else { return nil }
        if distance <= samples[0].distance { return samples[0] }
        if distance >= last.distance { return last }
        for index in 1..<samples.count where samples[index].distance >= distance {
            let a = samples[index - 1]
            let b = samples[index]
            let span = b.distance - a.distance
            let t = span > 0 ? (distance - a.distance) / span : 0
            return Sample(
                point: CGPoint(
                    x: a.point.x + (b.point.x - a.point.x) * t,
                    y: a.point.y + (b.point.y - a.point.y) * t),
                normal: unit(
                    CGPoint(
                        x: a.normal.x + (b.normal.x - a.normal.x) * t,
                        y: a.normal.y + (b.normal.y - a.normal.y) * t)),
                distance: distance)
        }
        return last
    }

    private static func unit(_ p: CGPoint) -> CGPoint {
        let length = max(0.0001, hypot(p.x, p.y))
        return CGPoint(x: p.x / length, y: p.y / length)
    }
}
