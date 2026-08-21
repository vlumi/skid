import Foundation

/// **What a track IS, as numbers** — for the author while building it, and for
/// the catalogue when choosing one.
///
/// Measured from the **layout**, not from the compiled centerline: a piece knows
/// it is a 90° sweep of a given radius, while a polyline only knows it bends, so
/// counting corners off samples would mean re-deriving (badly) what the catalog
/// already states exactly.
///
/// The point is a **deliberate spread** in the library — short/technical through
/// long/fast, a couple that climb — which needs the spread to be visible rather
/// than guessed at.
public struct TrackStats: Equatable, Sendable {
    /// Lap distance along the centerline, in world units.
    public var length: Double
    /// Corners, counted as **turns a driver takes** rather than arc pieces: a
    /// chicane authored as two arcs in one piece is two corners, while a sweep
    /// split across three identical pieces in the same direction is one. That is
    /// the number an author means by "how many corners".
    public var corners: Int
    /// The sharpest corner's radius, in world units — nil on a track with no
    /// corners at all. Small means technical.
    public var tightestRadius: Double?
    /// Total degrees turned, both directions summed. Against `length` this is
    /// what separates a flowing track from a twisty one.
    public var totalTurnDegrees: Double
    /// How many corners go each way, **as the player sees them** — a track that
    /// only turns one way is a bad sign worth seeing while building.
    ///
    /// Screen direction, not the model's `left` flag: that flag is a math-CCW
    /// turn, which renders CLOCKWISE on a y-down screen, so `left: true` is a
    /// screen-RIGHT corner (`PieceCatalog` names the same inversion `screenLeft`).
    /// Reporting the raw flag labelled every corner backwards to the author.
    public var leftCorners: Int
    public var rightCorners: Int
    /// Highest level the road reaches (0 = flat, 1 = one storey up).
    public var topLevel: Int
    /// Total climb in levels, counting only upward pieces — a lap that goes up
    /// and down twice climbs twice as much as its top level suggests.
    public var totalClimb: Double
    /// Pieces in the layout, which is the authoring cost of the track.
    public var pieceCount: Int
    /// How many separate straights there are, and the longest one — the two
    /// numbers that say whether a track has anywhere to use top speed.
    public var straightCount: Int
    public var longestStraight: Double

    /// **Corners per 1000 units** — the one derived number worth naming, since
    /// "twisty" is a ratio and not a count. Zero-length tracks report zero
    /// rather than dividing by nothing.
    public var cornersPerKilounit: Double {
        length > 0 ? Double(corners) * 1000 / length : 0
    }
}

extension TrackStats {
    /// Measure a layout. Nil only when the walk fails outright (an unknown
    /// piece), since a partial track is still worth measuring while building.
    public static func of(layout: TrackLayout) -> TrackStats? {
        let walk = layout.walk()
        guard walk.failure == nil else { return nil }
        return of(walk: walk)
    }

    public static func of(walk: WalkResult) -> TrackStats {
        var run = Run()
        for placed in walk.placed {
            run.stats.topLevel = max(
                run.stats.topLevel,
                Track.level(of: max(placed.entryHeight, placed.exitHeight)))
            if placed.climb > 0 { run.stats.totalClimb += placed.climb }
            // A gap has no road, so it neither straightens nor bends — but it
            // does interrupt a straight, which is the point of one.
            if placed.piece.kind == .gap {
                run.endStraight()
                continue
            }
            run.measure(placed)
        }
        run.endStraight()
        run.endCorner()
        run.stats.pieceCount = walk.placed.count
        // **The tightest corner worth naming.** A real corner turns at least a
        // quarter; below that it is a kink, and letting one set this number made
        // a flowing track read as tighter than its own hairpins. Falls back to
        // the tightest of anything at all when a track has only kinks, so the
        // number is never silently absent on a track that does bend.
        let real = run.corners.filter { $0.sweep >= 90 }
        run.stats.tightestRadius = (real.isEmpty ? run.corners : real).map(\.radius).min()
        return run.stats
    }

    /// The tally being built up while walking the pieces.
    ///
    /// A struct rather than a pile of local `var`s so the walk and the
    /// corner/straight bookkeeping are separable — the two together outgrew what
    /// one function should hold.
    private struct Run {
        var stats = TrackStats(
            length: 0, corners: 0, tightestRadius: nil, totalTurnDegrees: 0,
            leftCorners: 0, rightCorners: 0, topLevel: 0, totalClimb: 0,
            pieceCount: 0, straightCount: 0, longestStraight: 0)
        /// Which way the road is currently bending, so a corner can continue
        /// across piece boundaries — three 45° pieces in a row are one long
        /// corner to whoever drives it.
        var turningLeft: Bool?
        var runningStraight = 0.0
        var cornerSweep = 0.0
        var cornerRadius = Double.greatestFiniteMagnitude
        /// Each corner's sweep and tightest radius, for `tightestRadius`.
        var corners: [(sweep: Double, radius: Double)] = []

        mutating func endStraight() {
            guard runningStraight > 0 else { return }
            stats.straightCount += 1
            stats.longestStraight = max(stats.longestStraight, runningStraight)
            runningStraight = 0
        }

        mutating func endCorner() {
            guard cornerSweep > 0 else { return }
            corners.append((cornerSweep, cornerRadius))
            cornerSweep = 0
            cornerRadius = .greatestFiniteMagnitude
        }

        /// **Length from the SAMPLES, shape from the SEGMENTS.** The samples are
        /// the road as compiled and drawn — and the only thing that knows a
        /// fitter's solved curve, whose geometry is not in the catalog at all.
        /// The segments are what state a corner exactly.
        mutating func measure(_ placed: PlacedPiece) {
            let samples = placed.centerlineSamples()
            let pieceLength = zip(samples, samples.dropFirst())
                .reduce(0.0) { $0 + $1.0.distance(to: $1.1) }
            stats.length += pieceLength
            // A fitter has no catalog segments to read, so its length lands here
            // and its bends are not counted as corners: the piece exists to close
            // a gap the catalog cannot, and calling its curvature a corner would
            // inflate the count on any track that used one to join up.
            guard placed.fitter == nil, let chain = placed.piece.paths.first else {
                runningStraight += pieceLength
                return
            }
            for segment in chain {
                switch segment {
                case .straight(let length):
                    turningLeft = nil
                    endCorner()
                    runningStraight += Double(Coord(length).value)
                case .arc(let radius, let eighths, let left):
                    add(arcRadius: radius, eighths: eighths, left: left)
                }
            }
        }

        private mutating func add(arcRadius: Int, eighths: Int, left: Bool) {
            endStraight()
            let degrees = Double(eighths) * 45
            let worldRadius = Double(Coord(arcRadius).value)
            stats.totalTurnDegrees += degrees
            if turningLeft != left {
                endCorner()
                stats.corners += 1
                // `left: true` turns screen-RIGHT — see `leftCorners`.
                if left { stats.rightCorners += 1 } else { stats.leftCorners += 1 }
                turningLeft = left
            }
            cornerSweep += degrees
            cornerRadius = min(cornerRadius, worldRadius)
        }
    }
}
