import Foundation

/// Whether a layout is **saveable**, and if not, exactly why — so the editor
/// can explain a loose end rather than just graying out Save. Everything short
/// of saveable is a normal *editing* state, never an error.
public struct Validation: Equatable, Sendable {
    public enum Problem: Equatable, Sendable {
        /// The walk itself broke (unknown piece, empty).
        case walk(WalkResult.Failure)
        /// Loose ends remain — the graph isn't fully connected.
        case openEnds(Int)
        /// Two pieces overlap on the same layer where they may not.
        case overlap
        /// Not exactly one start-grid piece.
        case startCount(Int)
        /// Gates out of range, or seam 0 not marked, or a route crosses them
        /// in a different order.
        case gates
        /// The footprint doesn't fit the fixed canvas.
        case offCanvas
        /// The ring closes somewhere other than ground level — it climbed a
        /// ramp and never came back down, so the road would meet itself at two
        /// different heights.
        case unclosedHeight(Double)
    }

    public var problems: [Problem]
    public var isSaveable: Bool { problems.isEmpty }

    public init(problems: [Problem] = []) { self.problems = problems }
}

/// Validates a `TrackLayout` against the saveable rules (design doc §Validity).
public enum TrackValidator {
    /// The fixed canvas a layout must fit within (a format-version constant;
    /// the ~1.2:1 taller-aspect convention — tune with the catalog numbers).
    public static let canvas = Vec2(1600, 1333)

    /// Whether appending `id` keeps the layout **buildable** — i.e. it doesn't
    /// pave over itself or leave the canvas. The editor uses this to refuse the
    /// placement outright, which is far better than accepting it and showing a
    /// message the author can miss.
    ///
    /// Deliberately ignores the rules a work-in-progress is *expected* to break:
    /// loose ends, the gate count, and standing on the deck are all normal
    /// mid-build states, not reasons to block a piece.
    public static func canAppend(_ id: PieceID, to layout: TrackLayout) -> Bool {
        var candidate = layout
        candidate.pieces.append(id)
        let problems = validate(candidate).problems
        return !problems.contains { problem in
            switch problem {
            case .overlap, .offCanvas, .walk: return true
            case .openEnds, .gates, .startCount, .unclosedHeight: return false
            }
        }
    }

    public static func validate(_ layout: TrackLayout) -> Validation {
        var problems: [Validation.Problem] = []

        let walk = layout.walk()
        if let failure = walk.failure {
            return Validation(problems: [.walk(failure)])  // nothing else is meaningful
        }

        // 1. Every port mated.
        if !walk.openEnds.isEmpty {
            problems.append(.openEnds(walk.openEnds.count))
        }

        // 3. Exactly one start piece.
        let startCount = layout.pieces.filter { $0 == PieceCatalog.startPieceID }.count
        if startCount != 1 {
            problems.append(.startCount(startCount))
        }

        // 2. No disallowed same-layer overlap.
        if hasIllegalOverlap(walk.placed, ringClosed: walk.openEnds.isEmpty) {
            problems.append(.overlap)
        }

        // 4. Gates: 2…16, seam 0 included, in range.
        if !gatesValid(layout, placedCount: walk.placed.count) {
            problems.append(.gates)
        }

        // 5. Fits the canvas.
        if !fitsCanvas(walk.placed) {
            problems.append(.offCanvas)
        }

        // 6. Height comes home. A ring that climbs a ramp must descend before it
        // closes, or the road meets itself at two different heights — a
        // bridge to nowhere. (The walk only compares heights when auto-mating an
        // inlet, so a ring closing onto the origin could sneak through elevated.)
        // Only meaningful once the ring IS closed: mid-build, standing on the
        // deck is exactly what you'd expect.
        if walk.openEnds.isEmpty, let last = walk.placed.last, abs(last.exitHeight) > 0.001 {
            problems.append(.unclosedHeight(last.exitHeight))
        }

        return Validation(problems: problems)
    }

    // MARK: - Rule helpers

    /// Seam 0 marked, 2…16 gates, all in range. (The "every route crosses
    /// gates in the same cyclic order" rule only bites once forks compile —
    /// Phase B — since Phase A tracks are single-route by construction.)
    private static func gatesValid(_ layout: TrackLayout, placedCount: Int) -> Bool {
        let seams = Set(layout.gateSeams)
        guard seams.contains(0) else { return false }
        guard (2...16).contains(seams.count) else { return false }
        return layout.gateSeams.allSatisfy { (0..<placedCount).contains($0) }
    }

    /// Sample each piece's centerline to world points and check that no two
    /// non-adjacent pieces on the **same layer** actually cross — their
    /// centerlines coming within ~half a road width, which means the paved
    /// surfaces genuinely overlap (mere closeness between neighboring corners
    /// stays outside this). Legal crossable pairs and jump-gap unders are
    /// exempt.
    private static func hasIllegalOverlap(_ placed: [PlacedPiece], ringClosed: Bool) -> Bool {
        // Two ribbons touch when their centerlines are a FULL width apart (half
        // from each side) and overlap below that — so the threshold is the road
        // width, not half of it. (It was half, which let a lap sit half-on-top
        // of another and still validate.) A hair under, so ribbons that merely
        // graze aren't rejected.
        // **What counts as overlap (decided):** the ASPHALT only. Two ribbons
        // must not pave over each other, but their kerbs may abut or share
        // space — roads exactly 1U apart are legal and read as a shared kerb
        // between them, which is a real track feature and the tightest fit the
        // unit grid naturally produces (hairpin legs land exactly there).
        // Requiring kerb clearance instead would outlaw those fits. The
        // Consequences for the kerb pass: a kerb must never cover another
        // piece's asphalt (drivable surface beats decoration, so the band is
        // clipped by every other ribbon), and overlapping kerbs must merge into
        // one shared band rather than double-drawing. See docs/track-pieces.md.
        let minGap = Double(PieceCatalog.width) * 0.95
        // Sampled points + layer per piece (first path only; forks sample the
        // trunk — branch overlap gets full treatment in Phase B).
        let samples = placed.map { samplePoints($0) }

        let n = placed.count
        for i in placed.indices {
            for j in placed.indices where j > i {
                // Sequence-adjacent pieces share a port, so they always touch.
                if j == i + 1 { continue }
                // The first/last pair share the start seam ONLY once the ring
                // has closed. While it's still open, the last piece running up
                // alongside the start piece is a real overlap — and it's exactly
                // the placement that should have been refused, so exempting it
                // unconditionally let the offending piece land and then blamed
                // everything placed after it.
                if ringClosed && i == 0 && j == n - 1 { continue }
                // Different heights can't collide — that's a bridge crossing.
                if abs(placed[i].entryHeight - placed[j].entryHeight) > 0.5 { continue }
                if legallyCrossing(placed[i], placed[j]) { continue }
                if tooClose(samples[i], samples[j], minGap: minGap) { return true }
            }
        }
        return false
    }

    /// A crossable/crossable pair meeting at a shared point, or a jump gap a
    /// road runs under, is a permitted overlap.
    private static func legallyCrossing(_ a: PlacedPiece, _ b: PlacedPiece) -> Bool {
        let kinds = Set([a.piece.kind, b.piece.kind])
        if kinds == [.crossing] { return true }  // two crossables may cross
        if kinds.contains(.jump) { return true }  // a road may pass under a gap
        return false
    }

    private static func fitsCanvas(_ placed: [PlacedPiece]) -> Bool {
        guard !placed.isEmpty else { return false }
        let half = Double(PieceCatalog.width) / 2
        var pts: [Vec2] = []
        for p in placed { pts.append(contentsOf: samplePoints(p)) }
        let minX = pts.map(\.x).min()! - half
        let maxX = pts.map(\.x).max()! + half
        let minY = pts.map(\.y).min()! - half
        let maxY = pts.map(\.y).max()! + half
        return (maxX - minX) <= canvas.x && (maxY - minY) <= canvas.y
    }

    /// Coarse centerline samples of a piece's first path, as world `Vec2`.
    /// Enough for overlap/canvas checks; the compiler samples arcs finely.
    /// Delegates to the shared sampler (which walks segment chains, so a
    /// chicane or jog samples both of its arcs) at a coarse angular step.
    static func samplePoints(_ placed: PlacedPiece) -> [Vec2] {
        placed.centerlineSamples(degreesPerSample: 22.5)
    }

    /// Do two sampled centerlines come within `minGap` anywhere along them?
    ///
    /// This compares **segments**, not just sample points. Comparing points
    /// missed the obvious case: two straights crossing at right angles have
    /// their nearest *endpoints* far apart (339 units on a 4U crossing) even
    /// though the ribbons plainly intersect — so a figure-8 whose lobes met at
    /// the waist validated happily.
    private static func tooClose(_ a: [Vec2], _ b: [Vec2], minGap: Double) -> Bool {
        guard a.count >= 2, b.count >= 2 else {
            // Degenerate: fall back to point distance.
            for p in a where b.contains(where: { (p - $0).length < minGap }) { return true }
            return false
        }
        for i in 0..<(a.count - 1) {
            for j in 0..<(b.count - 1)
            where segmentDistance(a[i], a[i + 1], b[j], b[j + 1]) < minGap {
                return true
            }
        }
        return false
    }

    /// Shortest distance between two line segments. Segments that intersect
    /// return 0; otherwise the closest approach is from one segment's endpoint
    /// to the other segment (a standard property of convex shapes).
    private static func segmentDistance(_ p1: Vec2, _ p2: Vec2, _ q1: Vec2, _ q2: Vec2) -> Double {
        if segmentsIntersect(p1, p2, q1, q2) { return 0 }
        return min(
            min(p1.distance(toSegment: q1, q2), p2.distance(toSegment: q1, q2)),
            min(q1.distance(toSegment: p1, p2), q2.distance(toSegment: p1, p2)))
    }

    /// Proper segment intersection, by the sign of the four orientation tests.
    private static func segmentsIntersect(
        _ p1: Vec2, _ p2: Vec2, _ q1: Vec2, _ q2: Vec2
    ) -> Bool {
        let d1 = (p2 - p1).cross(q1 - p1)
        let d2 = (p2 - p1).cross(q2 - p1)
        let d3 = (q2 - q1).cross(p1 - q1)
        let d4 = (q2 - q1).cross(p2 - q1)
        return d1 * d2 < 0 && d3 * d4 < 0
    }
}
