import Foundation

/// How a piece runs vertically: level, or climbing/descending **half a level**
/// over its own length.
///
/// Pitch is an attribute of a placed piece, not a piece id — the catalog stays
/// a set of SHAPES, and "ramp" stops being a thing you pick and becomes a way
/// you lay road. In the share code, pitch is carried by mode-switch virtual
/// elements (and, until those land, by the ramp compounds); the in-memory
/// layout always holds it resolved per piece.
public enum Pitch: Int, Equatable, Sendable, Codable, CaseIterable {
    case flat = 0, up = 1, down = -1

    /// The height this pitch adds over one piece: half a level.
    public var delta: Double { Double(rawValue) * Track.levelHeight / 2 }
}

/// A track as the piece model stores it: an ordered piece-id list with each
/// piece's pitch, an origin pose (the start line, on the fixed canvas), the
/// gate seam indices, and a theme. This is exactly what the share code
/// carries. Geometry is never stored — it derives from walking the list.
public struct TrackLayout: Equatable, Sendable, Codable {
    public enum Theme: Int, Equatable, Sendable, Codable {
        case normal = 0, snow = 1, sand = 2
    }

    /// Pieces in ring order. The start-grid piece appears exactly once.
    public var pieces: [PieceID]
    /// Each piece's pitch, parallel to `pieces`. May run SHORT of it — direct
    /// `pieces` mutations don't maintain it, and a missing entry means flat
    /// (`pitch(at:)` is the accessor; `append`/`removeLastPiece` keep the two
    /// in step where non-flat pitch is possible). Never longer than `pieces`.
    public var pitches: [Pitch]
    /// Where piece 0 begins — the start line's pose on the canvas.
    public var origin: PiecePose
    /// Seam indices that are checkpoint gates (0 = the start/finish, always).
    public var gateSeams: [Int]
    public var theme: Theme

    public init(
        pieces: [PieceID], pitches: [Pitch] = [], origin: PiecePose = .origin,
        gateSeams: [Int] = [0], theme: Theme = .normal
    ) {
        self.pieces = pieces
        // Normalized to the piece count so equality is structural: trailing
        // flats and an absent array mean the same layout.
        self.pitches = TrackLayout.trimmed(pitches)
        self.origin = origin
        self.gateSeams = gateSeams
        self.theme = theme
    }

    /// The pitch of piece `index`; flat where the array runs short.
    public func pitch(at index: Int) -> Pitch {
        index < pitches.count ? pitches[index] : .flat
    }

    /// Append resolved (piece, pitch) pairs — what expansions produce — keeping
    /// the pitch array in step.
    public mutating func append(contentsOf run: [(id: PieceID, pitch: Pitch)]) {
        guard run.contains(where: { $0.pitch != .flat }) else {
            pieces += run.map(\.id)  // all flat: the short array already says so
            return
        }
        pitches += Array(repeating: .flat, count: pieces.count - pitches.count)
        pieces += run.map(\.id)
        pitches = TrackLayout.trimmed(pitches + run.map(\.pitch))
    }

    /// Remove the last piece and its pitch together.
    public mutating func removeLastPiece() {
        pieces.removeLast()
        if pitches.count > pieces.count { pitches.removeLast(pitches.count - pieces.count) }
    }

    /// Trailing flats dropped, so every equal layout has one representation.
    private static func trimmed(_ pitches: [Pitch]) -> [Pitch] {
        var result = pitches
        while result.last == .flat { result.removeLast() }
        return result
    }
}

/// A piece placed by the walk: which catalog piece, the entry pose, and the
/// exit pose(s) (two for a fork). The seam *before* this piece is `entrySeam`.
public struct PlacedPiece: Equatable, Sendable {
    public var id: PieceID
    public var piece: Piece
    public var entry: PiecePose
    public var exits: [PiecePose]
    /// Continuous **height** at this piece's entry (0 = ground, 1 = deck).
    /// The exit height is `entryHeight + climb`.
    public var entryHeight: Double
    /// Seam index at this piece's entry port.
    public var entrySeam: Int
    /// How this placement runs vertically. The piece's own `heightDelta`
    /// (full-climb compounds like the 2U ramp) and the pitch attribute
    /// (half-level climbs on ordinary shapes) never coexist on one placement.
    public var pitch: Pitch
    /// Whether the climb eases to a standstill at each end, or runs straight
    /// through into a neighbour that keeps climbing. The walk sets these from
    /// the sequence: a climb eases only where it FACES something that doesn't
    /// continue it — so a full climb split into halves is still one S-curve,
    /// not a terrace with a shelf at the apex.
    public var easeIn: Bool
    public var easeOut: Bool

    public init(
        id: PieceID, piece: Piece, entry: PiecePose, exits: [PiecePose],
        entryHeight: Double, entrySeam: Int, pitch: Pitch = .flat,
        easeIn: Bool = true, easeOut: Bool = true
    ) {
        self.id = id
        self.piece = piece
        self.entry = entry
        self.exits = exits
        self.entryHeight = entryHeight
        self.entrySeam = entrySeam
        self.pitch = pitch
        self.easeIn = easeIn
        self.easeOut = easeOut
    }

    /// The height this placement gains: the piece's own delta plus its pitch.
    public var climb: Double { piece.heightDelta + pitch.delta }

    /// Height at this piece's exit.
    public var exitHeight: Double { entryHeight + climb }

    /// Height at fraction `f` (0…1) along this piece, eased with **smoothstep**
    /// so a ramp meets the ground and deck smoothly rather than with hard
    /// creases. Flat pieces stay constant; the whole visual scale (road width,
    /// car size, wedge) reads off this.
    public func height(atFraction f: Double) -> Double {
        guard climb != 0 else { return entryHeight }
        let x = min(1, max(0, f))
        // Cubic Hermite from 0 to 1 with a chosen tangent at each end: 0 where
        // the climb eases against flat road, 1 (the run's own slope) where it
        // continues into a neighbour. Both eased is exactly smoothstep; both
        // continuing is exactly linear — so a chain of same-pitch pieces forms
        // one S: eased at its outer ends, straight through interior seams.
        let m0 = easeIn ? 0.0 : 1.0
        let m1 = easeOut ? 0.0 : 1.0
        let eased =
            m0 * (x * x * x - 2 * x * x + x) + (3 * x * x - 2 * x * x * x)
            + m1 * (x * x * x - x * x)
        return entryHeight + climb * eased
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
        guard delta > 0.001 else {
            let last = Double(pts.count - 1)
            return pts.enumerated().map { i, p in (p, height(atFraction: Double(i) / last)) }
        }
        // Subdivide each geometric span so no step climbs more than the cap.
        let needed = max(pts.count - 1, Int((delta / maxHeightStep).rounded(.up)))
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

/// The result of walking a layout: every piece placed in exact coordinates,
/// plus whatever ports are still open (loose ends) and any error that stopped
/// the walk. A fork-free ring that closes leaves `openEnds` empty.
public struct WalkResult: Equatable, Sendable {
    public enum Failure: Equatable, Sendable {
        case unknownPiece(PieceID)
        case emptyLayout
    }

    public var placed: [PlacedPiece]
    /// Poses still awaiting a mate (loose ends). Empty ⇒ fully connected.
    public var openEnds: [PiecePose]
    public var failure: Failure?

    public var isConnected: Bool { failure == nil && openEnds.isEmpty }
}

/// How far a loose end is from closing, split into the two currencies the unit
/// system spends: whole units along the axes, and whole units of *diagonal*
/// travel (the √2 part). The split is what tells an author which kind of piece
/// can still fix a gap — axis straights only ever repay the axis part, while a
/// √2 debt needs diagonal travel (a mirrored chicane, a 45° dogleg).
public struct ClosureGap: Equatable, Sendable {
    /// Axis offset in whole units — the `a` (rational) halves of the coordinate.
    public var axisX: Double
    public var axisY: Double
    /// Diagonal offset in whole units — the `b` (√2) halves.
    public var diagonalX: Double
    public var diagonalY: Double
    /// Eighths of a turn between the two headings (0 = already aligned).
    public var headingEighths: Int

    /// Nothing left to pay: same position, same heading.
    public var isClosed: Bool {
        axisX == 0 && axisY == 0 && !needsDiagonalTravel && headingEighths == 0
    }

    /// Whether any √2 debt remains. When false, the gap is pure axis travel and
    /// straights can close it; when true, no number of axis straights ever
    /// will — it needs diagonal travel to cancel (a mirrored chicane, a 45°
    /// dogleg).
    public var needsDiagonalTravel: Bool { diagonalX != 0 || diagonalY != 0 }

    /// What kind of work a gap still needs — the useful question, since the two
    /// currencies are repaid by completely different edits and one of them
    /// (a stranded √2 debt) can't be fixed by adding length at all.
    public enum Remedy: Equatable, Sendable {
        /// Already home.
        case closed
        /// The end faces the wrong way; turns are still needed.
        case turn(eighths: Int)
        /// Pure axis offset ahead of the end: lengthen straights on axis runs.
        case straights
        /// The target is BEHIND the loose end and correctly aligned — the loop
        /// overshot. No piece added here helps (you can't drive backwards);
        /// the fix is to shorten or remove a piece earlier in the run.
        case tooLong
        /// A √2 debt with the heading already correct. Adding *one* more 45°
        /// makes this worse, not better: the diagonal turns have to CANCEL —
        /// opposite-handed pairs, or a symmetric set all the way round (eight
        /// same-handed 45s cancel; two don't) — and the diagonal-facing runs
        /// have to balance against their opposites.
        case balanceDiagonals
    }

    /// Which edit closes the gap. `forward` is the loose end's heading, used to
    /// tell "short of the target" from "overshot it".
    public func remedy(facing forward: Heading) -> Remedy {
        if isClosed { return .closed }
        if headingEighths != 0 { return .turn(eighths: headingEighths) }
        if needsDiagonalTravel { return .balanceDiagonals }
        // Pure axis gap: is the target ahead of the end, or behind it?
        let dir = forward.unitStep
        let ahead = Double(dir.x.a) * axisX + Double(dir.y.a) * axisY
        return ahead < 0 ? .tooLong : .straights
    }
}

extension TrackLayout {
    /// The gap from `end` to the pose it must reach to close (by default the
    /// layout's origin — where a fork-free ring comes home), measured in the
    /// unit system so it reads as "2U east plus 1U of NE travel" rather than a
    /// raw float. Exact: the components come straight off the integer
    /// coordinates, so a closed loop reports exactly zero.
    public func closureGap(from end: PiecePose, to target: PiecePose? = nil) -> ClosureGap {
        let goal = target ?? origin
        let unit = Double(PieceCatalog.unit)
        let dx = goal.position.x - end.position.x
        let dy = goal.position.y - end.position.y
        // A Coord is (a + b√2)/2. The AXIS part is `a/2` in world length, so
        // dividing by the unit gives whole units. The DIAGONAL part is `b/2`
        // world lengths of √2 — and a unit of diagonal *travel* moves `b` by
        // `unit` (a 1U straight on a diagonal heading, or a tight 45's
        // displacement), so the diagonal count is `b / unit`, NOT `b/2/unit`.
        // Reporting it in the same currency the author spends is the whole
        // point of the readout.
        return ClosureGap(
            axisX: Double(dx.a) / 2 / unit, axisY: Double(dy.a) / 2 / unit,
            diagonalX: Double(dx.b) / unit, diagonalY: Double(dy.b) / unit,
            headingEighths: ((goal.heading.step - end.heading.step) % 8 + 8) % 8)
    }
}

extension TrackLayout {
    /// Walk the piece list from the origin, placing each piece and threading
    /// poses. Forks push their extra exit onto a stack of loose ends; a piece
    /// extends the current loose end, and when an exit lands exactly on an
    /// open end it auto-mates (that end is consumed). Pure and deterministic —
    /// no coordinates are read from storage, only derived here.
    public func walk() -> WalkResult {
        guard !pieces.isEmpty else {
            return WalkResult(placed: [], openEnds: [], failure: .emptyLayout)
        }

        var placed: [PlacedPiece] = []
        // Inlets a loose end can close onto: the start line (the origin, its
        // heading pointing INTO the first piece) plus each fork's not-yet-
        // continued exit. A loose end "mates" when it lands on an inlet exactly
        // and head-on. The origin inlet stays available the whole walk so a
        // ring closes onto it.
        var inlets: [(pose: PiecePose, height: Double)] = [(origin, 0)]
        // Loose ends still to be extended (LIFO stack). Start at the origin.
        var ends: [(pose: PiecePose, height: Double)] = [(origin, 0)]
        var seam = 0

        for (index, id) in pieces.enumerated() {
            guard let piece = PieceCatalog.piece(id) else {
                return WalkResult(
                    placed: placed, openEnds: ends.map(\.pose), failure: .unknownPiece(id))
            }
            // Continue the current loose end (LIFO — a fork's branch is
            // finished before returning to the trunk's pushed exit).
            guard let current = ends.popLast() else { break }  // stranded piece
            let entry = current.pose
            let entryHeight = current.height
            let exits = piece.paths.map { $0.exit(from: entry) }  // chain fold
            var placement = PlacedPiece(
                id: id, piece: piece, entry: entry, exits: exits,
                entryHeight: entryHeight, entrySeam: seam, pitch: pitch(at: index))
            // A climb runs straight through into a neighbour climbing the same
            // way; it eases only against everything else. (Sequence order is
            // placement order — forks are Phase B, so neighbours are i±1.)
            if let previous = placed.last, continues(previous.climb, placement.climb) {
                placement.easeIn = false
                placed[placed.count - 1].easeOut = false
            }
            placed.append(placement)
            seam += 1

            let exitHeight = placement.exitHeight
            // A fork's SECOND+ exits become both new loose ends AND inlets
            // (a later branch can rejoin them); the FIRST exit is the one we
            // continue next. Auto-mate each exit that lands on an existing
            // inlet at the same height instead of pushing it.
            for (k, exitPose) in exits.enumerated() {
                if let hit = inlets.firstIndex(where: {
                    mate(exitPose, $0.pose) && abs(exitHeight - $0.height) < 0.001
                }) {
                    inlets.remove(at: hit)  // closed this joint
                } else {
                    ends.append((exitPose, exitHeight))
                    if k > 0 { inlets.append((exitPose, exitHeight)) }
                }
            }
        }

        return WalkResult(placed: placed, openEnds: ends.map(\.pose), failure: nil)
    }

    /// Two consecutive climbs continue each other when both run the same way.
    private func continues(_ a: Double, _ b: Double) -> Bool {
        a != 0 && b != 0 && (a > 0) == (b > 0)
    }

    /// A loose end mates an inlet when their poses are **identical** — same
    /// position and same heading. The walk is forward-driven: an inlet stores
    /// the direction traffic flows *into* the joint (the origin faces the way
    /// piece 0 drives away; a fork branch-exit faces the way it drives on), so
    /// a returning end closes by flowing in the *same* direction, not head-on.
    private func mate(_ end: PiecePose, _ inlet: PiecePose) -> Bool {
        end == inlet
    }
}
