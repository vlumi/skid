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
    /// **Which laid pieces carry guard railings**, by piece index.
    ///
    /// A railing is not a property of a shape — the same bridge piece wants rails
    /// on one track and an open edge on another — so it is toggled on a placed
    /// piece, exactly like a decal, rather than doubling the catalog.
    ///
    /// **Empty by default, so a piece has no rails unless asked.** Rails used to
    /// be implied by climbing, which made "a bridge without railings" and "a
    /// railing on the flat" both unexpressible. Defaulting ON instead would force
    /// the encoding to distinguish "no toggle recorded" from "toggled off", and
    /// there are few enough tracks that adding rails back by hand is cheaper than
    /// carrying that ambiguity.
    ///
    /// Index-keyed, so this is the fifth thing every mutation remaps — see
    /// `TrackLayoutMutate`.
    public var railed: Set<Int>
    /// **How far each warp piece drops the road**, in levels, by piece index —
    /// negative, and only meaningful on a `.warp` piece.
    ///
    /// Index-keyed like `decals` and `railed`, so this is the sixth thing every
    /// mutation remaps (see `TrackLayoutMutate`). Keyed rather than parallel because
    /// a warp is rare: a track with none costs nothing.
    ///
    /// A warp with no entry drops one level, which is the overwhelmingly common
    /// case — the deck-to-ground jump.
    public var warpDrops: [Int: Double]
    public var theme: Theme

    public init(
        pieces: [PieceID], pitches: [Pitch] = [], origin: PiecePose = .origin,
        originHeight: Double = 0, gateSeams: [Int] = [0], theme: Theme = .normal,
        fitters: [Int: Fitter] = [:], decals: [Int: Decal] = [:],
        railed: Set<Int> = [], warpDrops: [Int: Double] = [:]
    ) {
        self.fitters = fitters
        self.decals = decals
        self.railed = railed
        self.warpDrops = warpDrops
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

    public func isRailed(at index: Int) -> Bool { railed.contains(index) }

    /// How far the warp at `index` drops the road. Defaults to a **full level** —
    /// the common case — and is clamped to never rise.
    public func warpDrop(at index: Int) -> Double {
        min(0, warpDrops[index] ?? -Track.levelHeight)
    }

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
    /// How many spans to cut a gapped piece into, so the hole in the asphalt has
    /// somewhere to live.
    ///
    /// 40 puts a sample every 12 units along a 4U jump. The gap's edges snap to
    /// whichever sample bounds them, so this is the accuracy of the hole: at 20
    /// (24-unit spacing) a boundary landing exactly ON a sample cost a full step at
    /// each end and the drawn gap came out 288 units instead of 240.
    static let gapSpans = 40

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
    /// **How far a warp drops the road**, in levels — always ≤ 0, and zero for
    /// every piece that is not a warp. Separate from `pitch` because it is not a
    /// slope: no road is travelled, so nothing is climbed or descended. It only
    /// says where the road resumes.
    public var warpDrop: Double

    public init(
        id: PieceID, piece: Piece, entry: PiecePose, exits: [PiecePose],
        entryHeight: Double, entrySeam: Int, pitch: Pitch = .flat,
        easeIn: Bool = true, easeOut: Bool = true, warpDrop: Double = 0
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
        // A warp only ever goes DOWN, and only a warp warps.
        self.warpDrop = piece.kind == .warp ? min(0, warpDrop) : 0
    }

    /// The height this placement gains: the piece's own delta, its pitch, and a
    /// warp's drop. A warp has no length, so this is the whole of its effect.
    public var climb: Double { piece.heightDelta + pitch.delta + warpDrop }

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
