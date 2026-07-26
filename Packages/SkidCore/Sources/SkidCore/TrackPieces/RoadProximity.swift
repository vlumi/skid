import Foundation

/// The one rule that decides when road may sit near road:
///
/// **Near in space is legal only when near along the road** — measured forward
/// along the chain, or the short way round *through the join*, where the gap
/// between the loose end and the start entry counts as road-to-be. Once the
/// ring closes that gap is zero and the metric is simply the ring metric.
///
/// A track is one continuous ribbon, so spatial proximity between two of its
/// points is not by itself an overlap: consecutive pieces touch at a port, a
/// tight curve's own samples crowd each other (on the tightest radius, two
/// centerline points under the overlap threshold are never more than ~119 units
/// apart along the arc — chord geometry, not a tuning choice), and the closing
/// corner legitimately hugs the start piece on its way home. A genuine
/// pave-over is different in exactly one way: the road travelled far before
/// coming back alongside itself. Arc distance is that difference, and the
/// join-gap term extends it to the ring being formed, so no separate case is
/// needed for "approaching the start" versus "closed".
///
/// This replaced three stacked piece-level exemptions — immediate neighbours
/// only, a fixed arc window wide enough to hide real pinches, and a "is the
/// loose end pointing home?" heuristic — each of which had a measured failure
/// on a real 41-piece design: the corner that closed the track was refused,
/// while the fixture laps the rules exist for were only caught by luck of which
/// piece pairs straddled the window.
struct RoadProximity {
    /// Two centerlines closer than this overlap in asphalt. A hair under the
    /// road width, so ribbons exactly 1U apart — the shared-kerb fit — stay
    /// legal by threshold rather than by exemption.
    static let minGap = Double(PieceCatalog.width) * 0.95

    /// How far apart along the road two points may be and still be allowed to
    /// touch in space.
    ///
    /// Anchored from both sides. Below it: continuity on the tightest curve
    /// tops out at ~119 units, and the measured closing approach on the real
    /// design (the corner sweeping past the start entry into the join) stays
    /// under ~250 through the gap. Above it: a genuine doubling-back needs at
    /// least a 180° turn, which costs ~600 units of road before it can pinch,
    /// and the lap fixtures' incursions measure ≥480 through the join. 2.5
    /// road widths sits in the gap between those bands.
    static let allowance = Double(PieceCatalog.width) * 2.5

    private let segments: [RoadSegment]
    private let grid: [GridKey: [Int]]
    /// Total centerline length of the chain.
    let totalArc: Double
    /// Straight-line gap from the loose end back to the start entry — the
    /// road-to-be that the through-metric charges for. Zero once closed;
    /// infinite when there is nothing to join.
    let joinGap: Double

    init(placed: [PlacedPiece], joinGap: Double) {
        var built: [RoadSegment] = []
        var arc = 0.0
        for (index, piece) in placed.enumerated() {
            let points = RoadProximity.densified(piece)
            for step in 1..<max(points.count, 1) {
                let length = points[step].distance(to: points[step - 1])
                built.append(
                    RoadSegment(
                        piece: index, a: points[step - 1], b: points[step],
                        arcMid: arc + length / 2))
                arc += length
            }
        }
        segments = built
        totalArc = arc
        self.joinGap = joinGap
        var cells: [GridKey: [Int]] = [:]
        for (index, segment) in built.enumerated() {
            for key in GridKey.covering(segment.a, segment.b, pad: 0) {
                cells[key, default: []].append(index)
            }
        }
        grid = cells
    }

    /// Is any same-chain pair of segments illegally close? `exempt` carries the
    /// caller's piece-pair policy (height layers, legal crossings).
    func hasIllegalPair(exempt: (Int, Int) -> Bool) -> Bool {
        for index in segments.indices {
            let segment = segments[index]
            var hit = false
            forEachNearby(segment.a, segment.b) { other in
                guard !hit, segments[other].piece > segment.piece else { return }
                let candidate = segments[other]
                guard
                    segmentDistance(segment.a, segment.b, candidate.a, candidate.b)
                        < Self.minGap
                else { return }
                guard !nearAlongRoad(segment.arcMid, candidate.arcMid) else { return }
                if !exempt(segment.piece, candidate.piece) { hit = true }
            }
            if hit { return true }
        }
        return false
    }

    /// Would an additional piece — given as a cached origin shape plus a world
    /// offset, so callers pay no per-query resampling — be illegally close to
    /// the existing chain?
    ///
    /// For the closure search: the piece sits `arcBefore` units of run beyond
    /// the chain's end, and the run is heading for the start entry —
    /// `exitToGoal` (straight-line, so never more than the road that will
    /// actually be laid) stands in for the rest of the way home.
    func conflicts(
        shape points: [Vec2], at offset: Vec2, arcBefore: Double, exitToGoal: Double,
        exempt: (Int) -> Bool
    ) -> Bool {
        let pieceArc = polylineLength(points)
        var inPiece = 0.0
        for step in 1..<max(points.count, 1) {
            let a = points[step - 1] + offset
            let b = points[step] + offset
            let length = a.distance(to: b)
            let mid = inPiece + length / 2
            var hit = false
            forEachNearby(a, b) { other in
                guard !hit, !exempt(segments[other].piece) else { return }
                let existing = segments[other]
                guard segmentDistance(a, b, existing.a, existing.b) < Self.minGap
                else { return }
                let along = (totalArc + arcBefore + mid) - existing.arcMid
                let through = (pieceArc - mid) + exitToGoal + existing.arcMid
                if min(along, through) > Self.allowance { hit = true }
            }
            if hit { return true }
            inPiece += length
        }
        return false
    }

    /// The exemption itself: are these two arc positions close along the road,
    /// counting the short way round through the (forming) join?
    private func nearAlongRoad(_ x: Double, _ y: Double) -> Bool {
        let along = abs(x - y)
        let through = totalArc - along + joinGap
        return min(along, through) <= Self.allowance
    }

    /// Visit stored segments near the given one (by grid cells, padded by the
    /// overlap threshold; may repeat — harmless, the checks are cheap). A
    /// callback instead of a returned array: this runs per search node, and the
    /// array churn was measurable in debug builds.
    private func forEachNearby(_ a: Vec2, _ b: Vec2, _ body: (Int) -> Void) {
        let cell = GridKey.cell
        let pad = Self.minGap
        let minX = Int(((min(a.x, b.x) - pad) / cell).rounded(.down))
        let maxX = Int(((max(a.x, b.x) + pad) / cell).rounded(.down))
        let minY = Int(((min(a.y, b.y) - pad) / cell).rounded(.down))
        let maxY = Int(((max(a.y, b.y) + pad) / cell).rounded(.down))
        for x in minX...maxX {
            for y in minY...maxY {
                guard let bucket = grid[GridKey(x: x, y: y)] else { continue }
                for index in bucket { body(index) }
            }
        }
    }

    private func polylineLength(_ points: [Vec2]) -> Double {
        var total = 0.0
        for step in 1..<max(points.count, 1) {
            total += points[step].distance(to: points[step - 1])
        }
        return total
    }

    /// Centerline samples with long spans subdivided, so no straight leaves a
    /// corridor the proximity test can't see into.
    static func densified(_ placed: PlacedPiece) -> [Vec2] {
        let step = Double(PieceCatalog.width) * 0.6
        let points = placed.centerlineSamples(degreesPerSample: 20)
        guard points.count >= 2 else { return points }
        var out: [Vec2] = [points[0]]
        for index in 1..<points.count {
            let span = points[index] - points[index - 1]
            let parts = max(1, Int((span.length / step).rounded(.up)))
            for part in 1...parts {
                out.append(points[index - 1] + span * (Double(part) / Double(parts)))
            }
        }
        return out
    }

    /// Shortest distance between two line segments: 0 if they intersect, else
    /// the closest endpoint-to-segment approach (a property of convex shapes).
    func segmentDistance(_ p1: Vec2, _ p2: Vec2, _ q1: Vec2, _ q2: Vec2) -> Double {
        if segmentsIntersect(p1, p2, q1, q2) { return 0 }
        return min(
            min(p1.distance(toSegment: q1, q2), p2.distance(toSegment: q1, q2)),
            min(q1.distance(toSegment: p1, p2), q2.distance(toSegment: p1, p2)))
    }

    /// Proper segment intersection, by the sign of the four orientation tests.
    private func segmentsIntersect(_ p1: Vec2, _ p2: Vec2, _ q1: Vec2, _ q2: Vec2) -> Bool {
        let d1 = (p2 - p1).cross(q1 - p1)
        let d2 = (p2 - p1).cross(q2 - p1)
        let d3 = (q2 - q1).cross(p1 - q1)
        let d4 = (q2 - q1).cross(p2 - q1)
        return d1 * d2 < 0 && d3 * d4 < 0
    }
}

/// One densified centerline segment, tagged with which piece it belongs to and
/// how far along the whole chain its midpoint sits.
private struct RoadSegment {
    var piece: Int
    var a: Vec2
    var b: Vec2
    var arcMid: Double
}

/// A cell in the spatial grid the segments are bucketed into. Cell size is one
/// road width — segments are shorter than that, so each touches at most a few.
private struct GridKey: Hashable {
    var x: Int
    var y: Int

    static let cell = Double(PieceCatalog.width)

    /// Every cell a segment's padded bounding box covers.
    static func covering(_ a: Vec2, _ b: Vec2, pad: Double) -> [GridKey] {
        let minX = Int(((min(a.x, b.x) - pad) / cell).rounded(.down))
        let maxX = Int(((max(a.x, b.x) + pad) / cell).rounded(.down))
        let minY = Int(((min(a.y, b.y) - pad) / cell).rounded(.down))
        let maxY = Int(((max(a.y, b.y) + pad) / cell).rounded(.down))
        var keys: [GridKey] = []
        for x in minX...maxX {
            for y in minY...maxY {
                keys.append(GridKey(x: x, y: y))
            }
        }
        return keys
    }
}
