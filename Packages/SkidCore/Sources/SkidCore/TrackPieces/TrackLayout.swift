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

/// Markings painted on a piece's road. Geometry is untouched — a decal changes
/// only what the piece looks like.
public enum Decal: Int, Equatable, Sendable, Codable, CaseIterable {
    /// An arrow along the road showing the driving direction, following the
    /// piece's own centerline (so it curves on a curve).
    case directionArrow = 1
    /// The same arrow in warning yellow — for the corner you want the driver
    /// looking at, not just the direction of travel.
    case warningArrow = 2
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
    /// The height piece 0 begins at, so a whole track can sit off the ground —
    /// a start line on the deck, a bridge that crosses under itself. Every
    /// other height derives from it by pitch, exactly as before; this is only
    /// the baseline the walk starts from.
    public var originHeight: Double
    /// Seam indices that are checkpoint gates. The start line's own seam is
    /// always among them — it is the finish line — and that seam is the start
    /// piece's index, not necessarily 0.
    ///
    /// **Always ascending**, enforced here rather than asked of every caller:
    /// order carries no meaning (a lap collects them all), so an unsorted
    /// spelling is the same track with a different code — and the share code is
    /// used as an identity. A `didSet` because this is a `public var` that the
    /// editor assigns directly; sorting only in `init` left that path open.
    public var gateSeams: [Int] {
        didSet { if !gateSeams.isSorted { gateSeams.sort() } }
    }
    /// **Solved shapes for the fitting pieces**, keyed by piece index.
    ///
    /// Every other piece's geometry comes from the catalog; a fitter's is solved
    /// when it is placed, because it exists precisely to make a shape the catalog
    /// cannot. Stored rather than re-derived so that every device walks identical
    /// numbers (see `Fitter`). An index with no entry is a fitter that has not
    /// been solved, which the validator refuses.
    public var fitters: [Int: Fitter]
    /// **Paint on laid pieces**, keyed by piece index — not pieces of their own.
    ///
    /// A decal is the same geometry with different markings, so making each one a
    /// catalog id would need an id per shape (and per pitch, and per future
    /// variant). Keyed here instead, one arrow serves every shape there is or will
    /// be, and a track with no decals costs nothing: the code section is omitted.
    ///
    /// Being index-keyed makes these the fourth thing every mutation remaps, with
    /// `gateSeams`, `fitters` and `pitches` — see `TrackLayoutMutate`.
    public var decals: [Int: Decal]
    public var theme: Theme

    public init(
        pieces: [PieceID], pitches: [Pitch] = [], origin: PiecePose = .origin,
        originHeight: Double = 0, gateSeams: [Int] = [0], theme: Theme = .normal,
        fitters: [Int: Fitter] = [:], decals: [Int: Decal] = [:]
    ) {
        self.fitters = fitters
        self.decals = decals
        self.pieces = pieces
        self.originHeight = originHeight
        // Normalized to the piece count so equality is structural: trailing
        // flats and an absent array mean the same layout.
        self.pitches = TrackLayout.trimmedPitches(pitches)
        self.origin = origin
        // Sorted for the same reason pitches are trimmed: one representation
        // per layout. Gate ORDER carries nothing — a lap collects them all —
        // so two spellings that differ only in order encoded to two codes,
        // which breaks the identity the share code is used for.
        self.gateSeams = gateSeams.sorted()
        self.theme = theme
    }

    /// The pitch of piece `index`; flat where the array runs short.
    public func pitch(at index: Int) -> Pitch {
        index < pitches.count ? pitches[index] : .flat
    }

    public func decal(at index: Int) -> Decal? { decals[index] }

    /// Append resolved (piece, pitch) pairs — what expansions produce. A run of
    /// end-inserts, so pitches (and any keyed data, of which there is none past
    /// the end) stay in step through the one remapping path.
    public mutating func append(contentsOf run: [(id: PieceID, pitch: Pitch)]) {
        for step in run { insert(step.id, pitch: step.pitch, at: pieces.count) }
    }

    public mutating func removeLastPiece() {
        remove(at: pieces.count - 1)
    }

    /// Trailing flats dropped, so every equal layout has one representation.
    /// Shared with the mutation API (`TrackLayoutMutate`), which pads to the
    /// piece count, edits, then re-trims.
    static func trimmedPitches(_ pitches: [Pitch]) -> [Pitch] {
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
    /// The solved shape, for a fitting piece only. Its geometry is not in the
    /// catalog — see `Fitter` — so the walk carries it here for whoever draws or
    /// drives the road.
    public var fitter: Fitter?
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

extension Array where Element: Comparable {
    /// Cheaper than `self == sorted()` — no allocation, and bails at the first
    /// descent. Worth it on a path that runs on every assignment.
    var isSorted: Bool {
        guard count > 1 else { return true }
        return !indices.dropFirst().contains { self[$0 - 1] > self[$0] }
    }
}
