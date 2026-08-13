import Foundation

/// **Where a track walls off its own road.**
///
/// A track can compile, pass every geometric check, and still be undrivable: the
/// road exists, and a wall sits on it. That is exactly what happened when a ramp's
/// earth filled from the ground rather than from the storey it stands on — a spiral
/// built fine, validated fine, and stopped the car dead at h=1.00 on its own
/// asphalt.
///
/// **This is a WARNING, not a gate.** The only thing validation gates is whether a
/// track appears in the race picker, so refusing a blocked track would make it
/// vanish with no explanation — worse than letting you drive into the wall and see
/// it. The editor badges the offending piece instead, and the track stays raceable.
///
/// Cheap on purpose: ~15 ms on a 300-point track, against 2.6 seconds for an AI lap
/// attempt — which is also a far worse oracle, since the AI stalls on tracks that
/// are perfectly drivable and would blame the author for its own driving.
extension Track {
    /// A stretch of road a car cannot pass, and the wall responsible.
    public struct Blockage: Equatable, Sendable {
        /// Index into `centerline` — the point that is walled in.
        public var point: Int
        /// What the car would be blocked by there.
        public var kind: Wall.Kind

        public init(point: Int, kind: Wall.Kind) {
            self.point = point
            self.kind = kind
        }
    }

    /// Every stretch of road a car driving it cannot pass.
    ///
    /// **Sampled down the centerline, and that is deliberate.** A railing stands on
    /// the road's edge and runs ALONG it — a car driving the road never touches one,
    /// so the middle of the road is exactly where a railing is invisible and an
    /// obstruction is not. Measured with the earth-base bug restored: a fully railed
    /// bridge ring reports 0 contacts, while the spiral that could not be driven
    /// reports 6, every one of them a wall lying perpendicular across the road.
    ///
    /// Sampling the road's WIDTH instead was the first attempt and was much worse:
    /// the car's center reaches to within one radius of the edge, which is exactly
    /// where the railing is, so every railed piece flagged — 79 consecutive points on
    /// the bridge ring.
    ///
    /// Empty on every shipped track and on both three-storey test tracks. A false
    /// positive teaches the author to ignore the warning, so quiet on real roads is
    /// the bar.
    public func blockages() -> [Blockage] {
        guard centerline.count > 1, heights.count == centerline.count else { return [] }
        var found: [Blockage] = []
        let count = centerline.count
        for index in centerline.indices {
            let point = centerline[index]
            let previous = centerline[(index - 1 + count) % count]
            if let kind = blockingWall(
                at: point, height: heights[index], movedFrom: previous)
            {
                found.append(Blockage(point: index, kind: kind))
            }
        }
        return found
    }

    /// The kind of wall that stops a car at `at`, if any.
    ///
    /// Uses `Wall.stops` — the sim's own rule, not a copy of it — so a warning here
    /// can never disagree with what a car actually hits.
    private func blockingWall(at: Vec2, height: Double, movedFrom: Vec2) -> Wall.Kind? {
        var car = CarState(position: at)
        car.height = height
        for wall in walls {
            // Only a wall the car is actually standing against: `stops` answers
            // "would this wall stop a car of this height", which is true of every
            // rail on the level for a car nowhere near it.
            guard at.distance(toSegment: wall.a, wall.b) < CarGeometry.radius else { continue }
            guard wall.stops(car: car, movedFrom: movedFrom) else { continue }
            return wall.kind
        }
        return nil
    }
}

/// Blocked pieces, for the editor.
///
/// The editor thinks in PIECES, but `Track.blockages()` reports centerline indices —
/// the compiler flattens the walk into one loop and keeps no map back. Rather than
/// add one to `Track` for a warning's sake, this asks each piece about its own
/// samples, which the walk already has.
extension TrackLayout {
    /// Which laid pieces a car could not drive through, by piece index.
    ///
    /// Compiles the track to get its walls, so it is a save-time question rather
    /// than a per-render one — ~15 ms on a 300-point track. Returns empty for a
    /// layout that cannot compile at all: an unfinished track has real problems the
    /// validator already reports, and adding "and it is blocked" to those is noise.
    public func blockedPieces() -> Set<Int> {
        guard let track = try? PieceCompiler.compile(self) else { return [] }
        return pieces(covering: track.blockages().map(\.point))
    }

    /// Which pieces a set of centerline indices fall in.
    ///
    /// Separate from `blockedPieces()` so it is testable: that one compiles from this
    /// layout, so no test can hand it a blocked track — the only way to produce one
    /// is a compiler bug, which is what the warning exists to catch. This takes the
    /// indices directly, so a test can name a point and check the piece.
    ///
    /// Counts the way the compiler builds: it seeds the loop with the first piece's
    /// entry point, then each piece contributes its samples from after its entry
    /// through its exit. The run of points belonging to a piece is therefore known
    /// without storing a map — and the seed is why the running total starts at 1.
    ///
    /// Not by matching coordinates: the compiler recenters the track, so a walk point
    /// is not a track point. Comparing the two is a mistake this codebase has made
    /// more than once.
    public func pieces(covering centerlineIndices: [Int]) -> Set<Int> {
        guard !centerlineIndices.isEmpty else { return [] }
        let walk = self.walk()
        var upperBounds: [(piece: Int, endsBefore: Int)] = []
        var running = 1
        for (piece, placed) in walk.placed.enumerated() {
            let samples = placed.heightedSamples(
                degreesPerSample: PieceCompiler.degreesPerSample)
            running += max(1, samples.count - 1)
            upperBounds.append((piece, running))
        }
        var pieces: Set<Int> = []
        for index in centerlineIndices {
            if let hit = upperBounds.first(where: { index < $0.endsBefore }) {
                pieces.insert(hit.piece)
            }
        }
        return pieces
    }
}
