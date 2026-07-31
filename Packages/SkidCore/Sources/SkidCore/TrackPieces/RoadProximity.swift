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
    /// Whether the ring is actually CLOSED, which `joinGap` cannot answer: a
    /// stretch can land on the start entry's position half a level above it, so
    /// the gap measures zero while the road is still open. Only the walk knows.
    let isClosed: Bool

    init(placed: [PlacedPiece], joinGap: Double, isClosed: Bool = false) {
        var built: [RoadSegment] = []
        var arc = 0.0
        for (index, piece) in placed.enumerated() {
            let samples = RoadProximity.densifiedHeighted(piece)
            for step in 1..<max(samples.count, 1) {
                let length = samples[step].point.distance(to: samples[step - 1].point)
                let height = (samples[step - 1].height + samples[step].height) / 2
                built.append(
                    RoadSegment(
                        piece: index, a: samples[step - 1].point, b: samples[step].point,
                        arcMid: arc + length / 2, top: height,
                        solidLow: RoadProximity.solidFloor(under: height)))
                arc += length
            }
        }
        segments = built
        totalArc = arc
        self.joinGap = joinGap
        self.isClosed = isClosed
        var cells: [GridKey: [Int]] = [:]
        for (index, segment) in built.enumerated() {
            for key in GridKey.covering(segment.a, segment.b, pad: 0) {
                cells[key, default: []].append(index)
            }
        }
        grid = cells
    }

    /// **How steeply two stretches must meet to count as a crossing** rather
    /// than an illegal overlap.
    ///
    /// At-grade crossings are IMPLICIT (docs/crossing-plan.md): nothing is
    /// declared or flagged, so geometry alone decides, and this angle is the
    /// whole of that decision. It is a threshold rather than a permission
    /// because everything downstream depends on the shared zone staying small:
    ///
    /// - a steep crossing's zone is about a road width across, so each road's
    ///   asphalt cleanly interrupts the other's edge lines and kerbs (which is
    ///   why crossings need no drawing code at all); a shallow merge would
    ///   erase them along its whole length;
    /// - the resolver's tiebreak for "which road is this car on" inside the
    ///   zone is heading alignment, which only discriminates when the two roads
    ///   genuinely disagree about direction;
    /// - a shallow overlap is almost always a mistake — a track grazing itself —
    ///   and refusing it is the only protection an author gets.
    ///
    /// **Tune this against real designs.** A square junction crosses at 90°; a
    /// pinched figure-eight whose lobes meet as a connected `)(` crosses
    /// shallower, and the number has to admit those while still refusing merges
    /// (a measured coil of four tight 90° turns meets itself at 3°).
    static let minCrossingAngle = 45.0

    /// Is any same-chain pair of segments illegally close? `exempt` carries the
    /// caller's piece-pair policy (height layers, legal crossings).
    func hasIllegalPair(exempt: (Int, Int) -> Bool) -> Bool {
        for index in segments.indices {
            let segment = segments[index]
            var hit = false
            forEachNearby(segment.a, segment.b) { other in
                guard !hit, segments[other].piece > segment.piece else { return }
                let candidate = segments[other]
                guard !clearVertically(segment, candidate) else { return }
                guard
                    segmentDistance(segment.a, segment.b, candidate.a, candidate.b)
                        < Self.minGap
                else { return }
                // The real gate: do the RIBBONS interpenetrate? Centerline
                // distance above is only the broad phase — see `overlapSlack`.
                let penetration = Self.ribbonPenetration(
                    segment.a, segment.b, candidate.a, candidate.b)
                if penetration <= Self.overlapSlack {
                    // No shared asphalt. One rule still applies: a stretch
                    // HOVERING over the join zone at an unjoinable height
                    // blocks the closure that must land there — the road-to-be
                    // has no segments yet, so only nearness to the join can
                    // see it. This protection used to ride on the over-broad
                    // centerline gate; it is explicit now.
                    if coversJoinZone(segment, candidate) { hit = true }
                    return
                }
                guard !nearAlongRoad(segment, candidate) else { return }
                // A steep meeting is a crossing, not a conflict — judged per
                // segment pair, which is what lets curves cross and lets a
                // crossing straddle piece boundaries without anyone declaring
                // anything. See `minCrossingAngle`.
                guard !crossesSteeply(segment, candidate) else { return }
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
    func conflicts(shape points: [Vec2], at offset: Vec2, run: RunContext) -> Bool {
        let pieceArc = polylineLength(points)
        var inPiece = 0.0
        for step in 1..<max(points.count, 1) {
            let a = points[step - 1] + offset
            let b = points[step] + offset
            let length = a.distance(to: b)
            let mid = inPiece + length / 2
            // Linear height along the arc — the real profile is smoothstepped,
            // but the search only prunes; `confirmed` re-checks the winner with
            // true geometry.
            let top = run.entryHeight + run.heightDelta * (pieceArc > 0 ? mid / pieceArc : 0)
            let low = Self.solidFloor(under: top)
            var hit = false
            forEachNearby(a, b) { other in
                guard !hit else { return }
                let existing = segments[other]
                guard
                    max(low - existing.top, existing.solidLow - top, 0)
                        <= Track.levelSeparation
                else { return }
                guard segmentDistance(a, b, existing.a, existing.b) < Self.minGap
                else { return }
                let along = (totalArc + run.arcBefore + mid) - existing.arcMid
                let through = (pieceArc - mid) + run.exitToGoal + existing.arcMid
                // Same two-tier rule as the validator's through-join side.
                let dh = abs(top - existing.top)
                let joinable =
                    dh <= Track.reachTolerance
                    || (through <= Self.allowance / 2 && dh <= through * Self.steepestSlope)
                let penetration = Self.ribbonPenetration(a, b, existing.a, existing.b)
                if penetration <= Self.overlapSlack {
                    // No shared asphalt: only the join-zone cover rule applies
                    // (mirrors the validator; see `coversJoinZone`).
                    if along > Self.allowance, through <= Self.allowance, !joinable {
                        hit = true
                    }
                    return
                }
                if along > Self.allowance, through > Self.allowance || !joinable {
                    hit = true
                }
            }
            if hit { return true }
            inPiece += length
        }
        return false
    }

    /// A pair that shares no asphalt but sits close THROUGH the join, at a
    /// height the closing road could not reach — a shelf parked over the spot
    /// where the ring must close. Same tiers as `nearAlongRoad`'s through
    /// side; the difference is polarity: there, joinable means exempt — here,
    /// NOT joinable within the join window means refused, because the covered
    /// gap is road-to-be with no segments of its own to defend it.
    ///
    /// **Only while there IS a join to protect.** On a closed ring the gap is
    /// already road, with its own segments, and the two stretches either side of
    /// the seam are ordinary neighbours — a ramp meeting flat road, say. Which
    /// pieces land there is pure spelling, so applying this to a closed ring made
    /// legality depend on where the piece list happened to start: the reported
    /// track was refused as built and accepted respelled, and the shipped clover
    /// disagreed with itself at four of its rotations.
    private func coversJoinZone(_ a: RoadSegment, _ b: RoadSegment) -> Bool {
        guard !isClosed else { return false }  // closed: nothing left to defend
        let along = abs(a.arcMid - b.arcMid)
        guard along > Self.allowance else { return false }  // plain neighbours
        let through = totalArc - along + joinGap
        guard through <= Self.allowance else { return false }  // not near the join
        let dh = abs(a.top - b.top)
        if dh <= Track.reachTolerance { return false }  // same level: joinable
        let joinable = through <= Self.allowance / 2 && dh <= through * Self.steepestSlope
        return !joinable
    }

    /// Vertical clearance between two segments' SOLID ranges — the same rule
    /// `Race.blocks` applies to walls: road at height h is solid from
    /// `trunc(h)` down, so a ramp is embankment all the way to the ground while
    /// a deck at 1 is thin air below itself. Ground under a deck clears by a
    /// full level; nothing clears a ramp, at either end — which is exactly how
    /// the compiled track drives (side rails + the mouth cap).
    private func clearVertically(_ a: RoadSegment, _ b: RoadSegment) -> Bool {
        max(a.solidLow - b.top, b.solidLow - a.top, 0) > Track.levelSeparation
    }

    /// Where the solid fill under road at `height` starts. `trunc`, with a hair
    /// of tolerance so a deck sample at 0.999… still counts as level 1 (thin),
    /// clamped so the interval can never invert.
    static func solidFloor(under height: Double) -> Double {
        min((height + 0.001).rounded(.down), height)
    }

    /// The exemption itself: are these two segments close along the road —
    /// forward, or the short way round through the (forming) join?
    ///
    /// The through side carries height conditions the forward side doesn't
    /// need: continuity along the road implies height continuity by itself,
    /// but the join zone is just PROXIMITY to the start entry. Two tiers,
    /// both measured on real tracks:
    ///
    /// - **Same level** (within a car's reach): the full approach window —
    ///   the closing corner legitimately sweeps beside the start from ~250
    ///   units out.
    /// - **Different heights**: only the tight continuity range, and only a
    ///   difference the road could actually climb over that distance at the
    ///   catalog's steepest pitch — a descending straight landing on the
    ///   entry has mid-segments half a level up, a road-width from the grid
    ///   (measured 0.25–0.48 over 60–120 through-units; must close). A flat
    ///   0.5 run PARKED across the grid pairs at ~240 through-units (must
    ///   not): the distance tier separates them, the slope bound backs it up.
    private func nearAlongRoad(_ a: RoadSegment, _ b: RoadSegment) -> Bool {
        let along = abs(a.arcMid - b.arcMid)
        if along <= Self.allowance { return true }
        let through = totalArc - along + joinGap
        guard through <= Self.allowance else { return false }
        let dh = abs(a.top - b.top)
        if dh <= Track.reachTolerance { return true }
        return through <= Self.allowance / 2 && dh <= through * Self.steepestSlope
    }

    /// The catalog's steepest climb: half a level over the shortest pitched
    /// piece (a tight 45°).
    static let steepestSlope: Double =
        (Track.levelHeight / 2) / (Double(PieceCatalog.tightRadius) * .pi / 4)

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
        densifiedHeighted(placed).map(\.point)
    }

    /// The same, carrying each sample's height (lerped across subdivisions —
    /// `heightedSamples` already refines sloped spans, so the lerp only fills
    /// the flat-distance subdivisions).
    static func densifiedHeighted(_ placed: PlacedPiece) -> [(point: Vec2, height: Double)] {
        let step = Double(PieceCatalog.width) * 0.6
        let samples = placed.heightedSamples(degreesPerSample: 20)
        guard samples.count >= 2 else { return samples }
        var out = [samples[0]]
        for index in 1..<samples.count {
            let span = samples[index].point - samples[index - 1].point
            let rise = samples[index].height - samples[index - 1].height
            let parts = max(1, Int((span.length / step).rounded(.up)))
            for part in 1...parts {
                let f = Double(part) / Double(parts)
                out.append(
                    (
                        point: samples[index - 1].point + span * f,
                        height: samples[index - 1].height + rise * f
                    ))
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

/// Where a candidate piece sits relative to the run being searched: how much
/// run precedes it, how far its exit still is from the goal, and its height
/// profile (entry plus delta, lerped along the piece).
struct RunContext {
    var arcBefore: Double
    var exitToGoal: Double
    var entryHeight: Double
    var heightDelta: Double
}

/// One densified centerline segment: which piece it belongs to, how far along
/// the whole chain its midpoint sits, and the vertical range it is solid over
/// (`solidLow…top` — see `solidFloor`).
private struct RoadSegment {
    var piece: Int
    var a: Vec2
    var b: Vec2
    var arcMid: Double
    var top: Double
    var solidLow: Double
}

extension RoadProximity {
    /// Whether these two stretches meet steeply enough to be a crossing.
    ///
    /// Undirected: a road crossing another head-on and tail-on are the same
    /// junction, so the angle is taken between the segments' lines, not their
    /// travel directions (`abs` on the dot product folds 91–180° back onto
    /// 0–89°).
    fileprivate func crossesSteeply(_ one: RoadSegment, _ other: RoadSegment) -> Bool {
        // **Both stretches must be at the same height.** An at-grade crossing is
        // two roads sharing tarmac; a road meeting a RAMP at 90° shares nothing
        // — a ramp is a solid embankment, so that is driving into a hillside,
        // and the sim's rails make it undrivable. Tripwire tests caught this
        // (ground across a ramp's low half, and a half-level road crossing the
        // ground), which is what they are for.
        //
        // Same height, not merely same 2D spot: compared against the tolerance
        // the surface model already uses for "is this the road I am on".
        guard abs(one.top - other.top) <= Track.surfaceTolerance else { return false }
        let u = one.b - one.a
        let v = other.b - other.a
        let lengths = u.length * v.length
        guard lengths > 0 else { return false }
        let cosine = min(1, abs(u.dot(v)) / lengths)
        let degrees = acos(cosine) * 180 / Double.pi
        return degrees >= Self.minCrossingAngle
    }
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
