import Foundation

/// **Where a piece's road actually runs** — the sampling that turns a catalog
/// shape into points, with the height at each one.
///
/// Split out of `TrackLayout.swift` on the file-length limit; this is one
/// coherent concern (geometry → samples) and the compiler, both renderers and the
/// icons all read it, so it earns its own file.
extension PlacedPiece {
    /// The world point a given fraction along this piece, measured by **distance**
    /// rather than by sample index.
    ///
    /// The distinction matters for anything that has to land at a precise place on a
    /// piece the sampler represents coarsely: a straight is just two endpoints, so
    /// rounding a fraction to the nearest index snaps to one end. That put a jump's
    /// launch line a whole unit before its lip.
    public func point(atFraction fraction: Double) -> Vec2? {
        let samples = centerlineSamples()
        guard let first = samples.first, let last = samples.last, samples.count > 1 else {
            return samples.first
        }
        guard fraction > 0 else { return first }
        guard fraction < 1 else { return last }

        var lengths: [Double] = [0]
        for index in 1..<samples.count {
            lengths.append(lengths[index - 1] + samples[index].distance(to: samples[index - 1]))
        }
        guard let total = lengths.last, total > 0 else { return first }
        let target = fraction * total
        for index in 1..<samples.count where lengths[index] >= target {
            let span = lengths[index] - lengths[index - 1]
            let local = span > 0 ? (target - lengths[index - 1]) / span : 0
            return samples[index - 1] + (samples[index] - samples[index - 1]) * local
        }
        return last
    }

    /// The piece's samples split into **solid runs** — the stretches that carry
    /// asphalt, with a jump's gap cut out. One run for every ordinary piece.
    ///
    /// Every drawing pass reads this rather than `heightedSamples` directly, so the
    /// surface, the drop shadow, the guard rails and the kerbs all lose the gap
    /// together, from one definition. Getting that wrong is this project's most
    /// expensive recurring bug — the drawing and the physics disagreeing — and a
    /// jump shipped once as solid-looking road for exactly that reason: the gap was
    /// real to `surface(at:)` and invisible to every renderer.
    ///
    /// Sample-accurate rather than interpolated: the gap's ends land on whichever
    /// samples bound them, which is why a gapped piece is densified
    /// (`PlacedPiece.gapSpans`) instead of relying on a straight's two endpoints.
    public func solidRuns(degreesPerSample: Double = 6, maxHeightStep: Double = 0.05)
        -> [[(point: Vec2, height: Double)]]
    {
        let samples = heightedSamples(
            degreesPerSample: degreesPerSample, maxHeightStep: maxHeightStep)
        guard let gap = piece.gapSpan, samples.count > 1 else {
            return samples.isEmpty ? [] : [samples]
        }
        let last = Double(samples.count - 1)
        var runs: [[(point: Vec2, height: Double)]] = []
        var current: [(point: Vec2, height: Double)] = []
        for (index, sample) in samples.enumerated() {
            if gap.contains(Double(index) / last) {
                // A run needs two points to be a ribbon at all.
                if current.count > 1 { runs.append(current) }
                current = []
            } else {
                current.append(sample)
            }
        }
        if current.count > 1 { runs.append(current) }
        return runs
    }

    /// World-space centerline samples paired with the **height** at each one
    /// (eased along the piece). Renderers use this to vary road width / car
    /// scale continuously with elevation — a ramp widens as it climbs, no
    /// special-casing. First path only (the driven trunk).
    ///
    /// A **sloped** piece is densified by its climb as well as by its curvature.
    /// Curvature alone leaves a straight ramp with just its two endpoints, so the
    /// height would step 0 → 1 in one go: the smoothstep never appears, and the
    /// road is a cliff rather than a slope. `maxHeightStep` caps how much any one
    /// step may climb.
    public func heightedSamples(degreesPerSample: Double = 6, maxHeightStep: Double = 0.05)
        -> [(point: Vec2, height: Double)]
    {
        let pts = centerlineSamples(degreesPerSample: degreesPerSample)
        guard pts.count > 1 else { return pts.map { ($0, entryHeight) } }
        let delta = abs(climb)
        // A piece whose surface changes ALONG it needs interior points to carry
        // that change, exactly as a climb does. A jump is the case: a flat
        // straight samples only its two endpoints, so its gap had nowhere to
        // live and the hole in the asphalt silently never appeared.
        let minimumSpans = piece.gapSpan == nil ? 0 : Self.gapSpans
        guard delta > 0.001 || minimumSpans > pts.count - 1 else {
            let last = Double(pts.count - 1)
            return pts.enumerated().map { i, p in (p, height(atFraction: Double(i) / last)) }
        }
        // Subdivide each geometric span so no step climbs more than the cap.
        let needed = max(
            pts.count - 1, minimumSpans, Int((delta / maxHeightStep).rounded(.up)))
        let perSpan = Int((Double(needed) / Double(pts.count - 1)).rounded(.up))
        var dense: [(point: Vec2, height: Double)] = []
        let spans = pts.count - 1
        for span in 0..<spans {
            let a = pts[span]
            let b = pts[span + 1]
            for step in 0..<perSpan {
                let local = Double(step) / Double(perSpan)
                let fraction = (Double(span) + local) / Double(spans)
                dense.append((a + (b - a) * local, height(atFraction: fraction)))
            }
        }
        dense.append((pts[pts.count - 1], height(atFraction: 1)))
        return dense
    }

    /// World-space centerline samples for one of this piece's paths, arcs
    /// densified to ~`degreesPerSample`. Shared by the compiler (building the
    /// runtime centerline) and the editor (drawing a partial, not-yet-closed
    /// layout) so both draw identical geometry. Includes both endpoints.
    public func centerlineSamples(path pathIndex: Int = 0, degreesPerSample: Double = 6)
        -> [Vec2]
    {
        // A fitter's road is its solved curve-straight-curve, not a catalog path.
        if let fitter {
            return Self.fitterSamples(
                fitter, from: entry, degreesPerSample: degreesPerSample)
        }
        guard pathIndex < piece.paths.count else { return [entry.position.vec2] }
        // Walk the chain segment by segment, concatenating samples. Each
        // segment starts where the previous ended, so drop the duplicated
        // joint point when appending.
        let chain = piece.paths[pathIndex]
        var points: [Vec2] = [entry.position.vec2]
        for (segment, pose) in zip(chain, chain.segmentEntries(from: entry)) {
            let sampled = Self.samples(
                of: segment, from: pose, degreesPerSample: degreesPerSample)
            points.append(contentsOf: sampled.dropFirst())
        }
        return points
    }

    /// A fitter's centerline: arc, straight, mirrored arc, sampled in world space.
    ///
    /// Walked in floating point from the entry pose — the one piece for which that
    /// is right, since its shape is a solved float and its exit is pinned
    /// separately (the inlet it closes onto). Any drift over the piece's own
    /// length is ~1e-12 units, twelve orders below a device pixel.
    static func fitterSamples(
        _ fitter: Fitter, from entry: PiecePose, degreesPerSample: Double
    ) -> [Vec2] {
        // NEGATIVE for a left step. `Fitter.displacement` measures "left" as
        // `heading − 90°`, which in this y-down world is a NEGATIVE rotation; the
        // sweep below turns by a positive angle for a positive turn. Getting this
        // backwards mirrored the piece about its entry heading — the road left its
        // own exit by 198 units on a real track, while the validator (which uses
        // `displacement`) saw nothing wrong, because both sides of that comparison
        // shared the same convention.
        let side = fitter.stepsLeft ? -1.0 : 1.0
        var heading = entry.heading.radians
        var at = entry.position.vec2
        var points: [Vec2] = [at]

        func sweep(_ turn: Double) {
            guard abs(turn) > 1e-12 else { return }
            let steps = max(
                1, Int((abs(turn) * 180 / .pi / degreesPerSample).rounded(.up)))
            let center =
                at + Vec2(angle: heading + (turn > 0 ? .pi / 2 : -.pi / 2))
                * fitter.radius
            let startAngle = atan2(at.y - center.y, at.x - center.x)
            for step in 1...steps {
                let a = startAngle + turn * Double(step) / Double(steps)
                points.append(center + Vec2(angle: a) * fitter.radius)
            }
            at = points[points.count - 1]
            heading += turn
        }

        sweep(side * fitter.angle)
        if fitter.length > 0 {
            at += Vec2(angle: heading) * fitter.length
            points.append(at)
        }
        sweep(-side * fitter.angle)
        return points
    }

    /// Sample ONE segment from a starting pose, both endpoints included.
    private static func samples(
        of segment: Piece.Segment, from entry: PiecePose, degreesPerSample: Double
    ) -> [Vec2] {
        let start = entry.position.vec2
        switch segment {
        case .straight:
            return [start, segment.exit(from: entry).position.vec2]
        case .arc(let radius, let eighths, let left):
            let sweepDeg = Double(eighths) * 45
            let steps = max(1, Int((sweepDeg / degreesPerSample).rounded(.up)))
            let toCenter = entry.heading.radians + (left ? .pi / 2 : -.pi / 2)
            let center = start + Vec2(angle: toCenter) * Double(radius)
            let startAngle = atan2(start.y - center.y, start.x - center.x)
            let sweep = (left ? 1.0 : -1.0) * Double(eighths) * .pi / 4
            return (0...steps).map { k in
                let a = startAngle + sweep * Double(k) / Double(steps)
                return center + Vec2(angle: a) * Double(radius)
            }
        }
    }
}
