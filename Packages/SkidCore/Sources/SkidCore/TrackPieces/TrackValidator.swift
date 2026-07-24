import Foundation

/// Whether a layout is **saveable**, and if not, exactly why — so the editor
/// can explain a loose end rather than just greying out Save. Everything short
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
        if hasIllegalOverlap(walk.placed) {
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
    /// surfaces genuinely overlap (mere closeness between neighbouring corners
    /// stays outside this). Legal crossable pairs and jump-gap unders are
    /// exempt.
    private static func hasIllegalOverlap(_ placed: [PlacedPiece]) -> Bool {
        let minGap = Double(PieceCatalog.width) * 0.5
        // Sampled points + layer per piece (first path only; forks sample the
        // trunk — branch overlap gets full treatment in Phase B).
        let samples = placed.map { samplePoints($0) }

        let n = placed.count
        for i in placed.indices {
            for j in placed.indices where j > i {
                // Skip sequence-adjacent pieces, and the ring wraparound pair
                // (first & last) that share the start seam — they touch legally.
                if j == i + 1 { continue }
                if i == 0 && j == n - 1 { continue }
                if placed[i].entryLayer != placed[j].entryLayer { continue }
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
    static func samplePoints(_ placed: PlacedPiece) -> [Vec2] {
        guard let segment = placed.piece.paths.first else { return [placed.entry.position.vec2] }
        switch segment {
        case .straight:
            return [placed.entry.position.vec2, placed.exits[0].position.vec2]
        case .arc(let radius, let eighths, _):
            // Sample the arc at ~1 point per 45° plus the endpoints.
            let steps = max(2, eighths + 1)
            return arcSamples(
                entry: placed.entry, exit: placed.exits[0], radius: radius,
                eighths: eighths, steps: steps)
        }
    }

    private static func arcSamples(
        entry: PiecePose, exit: PiecePose, radius: Int, eighths: Int, steps: Int
    ) -> [Vec2] {
        // Reconstruct the arc centre in float space and sweep it.
        let start = entry.position.vec2
        let startHeading = entry.heading.radians
        // Centre is 90° to the turn side; infer side from the exit turn.
        let left = exit.heading.step == Heading(entry.heading.step + eighths).step
        let toCentre = startHeading + (left ? .pi / 2 : -.pi / 2)
        let centre = start + Vec2(angle: toCentre) * Double(radius)
        let startAngle = atan2(start.y - centre.y, start.x - centre.x)
        let sweep = (left ? 1.0 : -1.0) * Double(eighths) * .pi / 4
        return (0...steps).map { k in
            let a = startAngle + sweep * Double(k) / Double(steps)
            return centre + Vec2(angle: a) * Double(radius)
        }
    }

    /// Any sampled point of `a` within `minGap` of any of `b`.
    private static func tooClose(_ a: [Vec2], _ b: [Vec2], minGap: Double) -> Bool {
        let g2 = minGap * minGap
        for p in a {
            for q in b where (p - q).lengthSquared < g2 { return true }
        }
        return false
    }
}
