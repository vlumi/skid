import Foundation

/// **Which segments are near this point** — a uniform grid over the centerline,
/// so a track query looks at a handful of segments instead of all of them.
///
/// Every "am I on the road / how high is it here" question scanned the whole
/// centerline: ~300 segments on a real track, several times per car per tick,
/// plus the AI's probes and the mark recorder's. Measured on the reporting
/// 4-storey track: `height(at:)` 40 µs and `surface(at:)` 84 µs per call, and
/// the whole sim tick 4.8 ms against a 16.7 ms frame — the choppiness left over
/// after the render cache, and most of an SE's frame.
///
/// **Bucketed by EXTENT, searched by RING.** The first cut bucketed each segment
/// into every cell within the road's widest reach of it, so that one cell lookup
/// would hold everything relevant. That inflates rather than reduces: with a
/// reach of 216 units on a 192-unit cell every segment lands in ~9 cells, and a
/// bucket held 101 of 303 segments — a third of the scan, for none of the
/// savings. A segment now occupies only the cells it actually crosses, and a
/// query walks out ring by ring until the nearest hit is provably closer than the
/// next ring can reach.
///
/// **Deliberately not part of `Track`'s stored state.** `Track` is `Codable` and
/// `Equatable`, and an index is derived data: encoding it would bloat every
/// saved track and make two identical tracks compare unequal over a cache. It is
/// built on demand and memoised per centerline (see `Track.segmentIndex`).
struct TrackSegmentIndex: Sendable {
    /// Cell edge in world units. Segments are ~10–60 units long, so this holds a
    /// few per cell — small enough that a ring is cheap, large enough that a
    /// query rarely needs more than the first two.
    static let cell: Double = 128

    private struct Cell: Hashable {
        var column: Int
        var row: Int
    }

    /// Segment indices per cell, each list ascending.
    ///
    /// Keyed by the (column, row) pair rather than a packed integer: packing
    /// needs a stride, a stride from the map width cannot represent a negative
    /// column, and off-map queries are real (the editor and the debug overlay
    /// make them). A pair key cannot alias.
    private var buckets: [Cell: [Int]] = [:]
    /// Segments long enough that bucketing them by extent is not worth it, plus
    /// a degenerate track's. Always tested. Normally empty.
    private var always: [Int] = []

    init(centerline: [Vec2]) {
        guard centerline.count > 1 else {
            always = Array(centerline.indices)
            return
        }
        for i in centerline.indices {
            let a = centerline[i]
            let b = centerline[(i + 1) % centerline.count]
            let columns = Self.cellIndex(min(a.x, b.x))...Self.cellIndex(max(a.x, b.x))
            let rows = Self.cellIndex(min(a.y, b.y))...Self.cellIndex(max(a.y, b.y))
            guard columns.count * rows.count <= 32 else {
                always.append(i)
                continue
            }
            // The segment's bounding box, not its exact traversal: a diagonal
            // lists a few cells it only clips. Harmless — an extra candidate
            // costs one distance test, while missing one would be wrong.
            for column in columns {
                for row in rows {
                    buckets[Cell(column: column, row: row), default: []].append(i)
                }
            }
        }
        // **Ascending, which is what makes a tie break the same way.** Callers
        // keep the first of equally-scoring segments (a strict `<`), so a bucket
        // in another order could name a different segment than the full scan for
        // the same point — two segments meeting at a shared endpoint score
        // identically for a point on it, and that is where a car sits.
        for cell in buckets.keys {
            buckets[cell]?.sort()
        }
    }

    /// Which cell a coordinate falls in. **`floor`, not `Int(_:)`** — truncation
    /// rounds toward zero, so -0.5 and +0.5 both landed in cell 0 and the strip
    /// just left of the origin aliased onto the strip just right of it. Tracks
    /// live in positive coordinates, but the editor and the debug overlay ask
    /// about points outside the map, and an alias there is a wrong answer.
    static func cellIndex(_ value: Double) -> Int { Int((value / cell).rounded(.down)) }

    /// Every segment within `radius` of `p`, ascending, plus the `always` list.
    ///
    /// The caller states how far it cares about; this returns a superset of what
    /// lies inside that, which is what keeps it an exact optimisation rather than
    /// an approximation. Ring `n` spans cells whose nearest edge is `(n-1) *
    /// cell` away, so the rings needed are bounded by `radius`.
    func candidates(near p: Vec2, within radius: Double) -> [Int] {
        let rings = max(0, Int((radius / Self.cell).rounded(.up)))
        let column = Self.cellIndex(p.x)
        let row = Self.cellIndex(p.y)
        var found = always
        for dColumn in -rings...rings {
            for dRow in -rings...rings {
                if let list = buckets[Cell(column: column + dColumn, row: row + dRow)] {
                    found.append(contentsOf: list)
                }
            }
        }
        // Duplicates are possible (a segment spans several cells in range) and
        // harmless to a min-search, but sorting keeps the tie rule above and
        // uniquing keeps the list short.
        return found.count > 1 ? Array(Set(found)).sorted() : found
    }

    /// The nearest segment to `p` and its distance, searched ring by ring so the
    /// work scales with how far the answer is rather than with the track's size.
    ///
    /// Exact: a ring is only accepted once the best hit so far is closer than the
    /// next ring's nearest possible cell edge, so no closer segment can be
    /// hiding further out. Returns nil only for an empty index.
    func nearest(
        to p: Vec2, centerline: [Vec2], accept: (Int) -> Bool = { _ in true }
    ) -> (segment: Int, distance: Double)? {
        let column = Self.cellIndex(p.x)
        let row = Self.cellIndex(p.y)
        var best: (segment: Int, distance: Double)?
        func consider(_ i: Int) {
            guard accept(i) else { return }
            let a = centerline[i]
            let b = centerline[(i + 1) % centerline.count]
            let distance = p.distance(toSegment: a, b)
            // `<` keeps the LOWEST index of equals, matching the full scan.
            if best == nil || distance < best!.distance { best = (i, distance) }
        }
        for i in always { consider(i) }
        // Bounded by the grid's own span: past that there are no more cells to
        // find, so an unbounded loop would spin.
        let maxRing = maxRings
        var ring = 0
        while ring <= maxRing {
            for cell in cells(inRing: ring, column: column, row: row) {
                for i in buckets[cell] ?? [] { consider(i) }
            }
            // Everything in rings beyond this one is at least this far away.
            let nextRingFloor = Double(ring) * Self.cell
            if let best, best.distance <= nextRingFloor { return best }
            ring += 1
        }
        return best
    }

    /// The cells forming the square ring at Chebyshev distance `ring`.
    private func cells(inRing ring: Int, column: Int, row: Int) -> [Cell] {
        guard ring > 0 else { return [Cell(column: column, row: row)] }
        var found: [Cell] = []
        for offset in -ring...ring {
            found.append(Cell(column: column + offset, row: row - ring))
            found.append(Cell(column: column + offset, row: row + ring))
        }
        for offset in (-ring + 1)...(ring - 1) {
            found.append(Cell(column: column - ring, row: row + offset))
            found.append(Cell(column: column + ring, row: row + offset))
        }
        return found
    }

    /// How many rings can possibly hold anything — the grid's own diagonal, so a
    /// search from far off the map still terminates.
    private var maxRings: Int {
        guard
            let minColumn = buckets.keys.map(\.column).min(),
            let maxColumn = buckets.keys.map(\.column).max(),
            let minRow = buckets.keys.map(\.row).min(),
            let maxRow = buckets.keys.map(\.row).max()
        else { return 0 }
        return (maxColumn - minColumn) + (maxRow - minRow) + 2
    }
}

extension Track {
    /// The index for this track's centerline, built once and reused.
    ///
    /// Memoised in a process-wide cache rather than stored on the value: `Track`
    /// is a `Codable`/`Equatable` value that gets copied constantly (every
    /// `Race` holds one), so a stored index would be encoded, compared, and
    /// copied for nothing. Keyed by identity AND shape, so an edited track — or
    /// a test's ad-hoc one built under the same id — never reads a stale index.
    var segmentIndex: TrackSegmentIndex {
        TrackIndexCache.shared.index(for: self)
    }
}

/// A tiny process-wide memo for segment indices.
///
/// Locked rather than actor-isolated: the sim is synchronous and its queries are
/// on whatever thread stepped it, so an `async` boundary here would spread
/// through every caller of `height(at:)`.
private final class TrackIndexCache: @unchecked Sendable {
    static let shared = TrackIndexCache()

    private struct Key: Hashable {
        var id: String
        var points: Int
        /// A cheap shape digest, so two different tracks sharing an id (ad-hoc
        /// test tracks all use "") cannot collide.
        var digest: Int
    }

    private let lock = NSLock()
    private var cached: [Key: TrackSegmentIndex] = [:]

    func index(for track: Track) -> TrackSegmentIndex {
        let key = Key(
            id: track.id, points: track.centerline.count, digest: track.shapeDigest)
        lock.lock()
        if let found = cached[key] {
            lock.unlock()
            return found
        }
        lock.unlock()
        let built = TrackSegmentIndex(centerline: track.centerline)
        lock.lock()
        // A handful of tracks are ever live (the race's, a ghost's, the
        // editor's preview); a test suite makes many. Clear rather than evict —
        // the cost of a rebuild is milliseconds and the cache exists to serve
        // the hot loop, not to be complete.
        if cached.count > 64 { cached.removeAll() }
        cached[key] = built
        lock.unlock()
        return built
    }
}

extension Track {
    /// Enough of the centerline's shape to tell two tracks apart, without
    /// hashing every point on every query.
    fileprivate var shapeDigest: Int {
        var hasher = Hasher()
        hasher.combine(width)
        hasher.combine(centerline.count)
        // Ends and a few strided samples: two tracks that agree on all of these
        // and on their point count are the same track in every real case.
        for point in stride(from: 0, to: centerline.count, by: max(1, centerline.count / 8)) {
            hasher.combine(centerline[point].x)
            hasher.combine(centerline[point].y)
        }
        if let last = centerline.last {
            hasher.combine(last.x)
            hasher.combine(last.y)
        }
        for height in stride(from: 0, to: heights.count, by: max(1, heights.count / 8)) {
            hasher.combine(heights[height])
        }
        return hasher.finalize()
    }
}
