import Foundation

/// One catalog piece's stable id (a varint on the wire: 0…127 one byte, ≥128
/// two bytes). The one-byte range is core geometry; decals/variants live at
/// 128+. Ids are frozen only at the format's first public release.
public typealias PieceID = Int

/// What a piece does to the walk when it's placed: how many ports it has, the
/// pose change from entry to each exit, its layer effect, and the shape data
/// the compiler needs to emit centerline + walls.
///
/// A piece is authored in a **local frame** whose entry port is the identity
/// pose (position 0, heading east); `exits` are the resulting poses in that
/// frame. Placing the piece maps the local frame onto the current walk pose.
public struct Piece: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A plain drivable segment (straights, curves, ramps, start, decals).
        case road
        /// A crossable straight — may overlap one other crossable at a
        /// coincident midpoint (the bridgeless-8 intersection).
        case crossing
        /// One entry, two exits — a route fork (join is the mirrored piece,
        /// still authored as two entries → one exit, encoded reversed).
        case fork
        /// Launch lip · road gap · landing; the gap may be crossed beneath.
        case jump
    }

    /// How the centerline is shaped between entry and an exit.
    public enum Segment: Equatable, Sendable {
        /// Straight run of `length` along the entry heading.
        case straight(length: Int)
        /// Arc of `radius`, turning `eighths` × 45°, `left` or right.
        case arc(radius: Int, eighths: Int, left: Bool)
    }

    public var id: PieceID
    public var kind: Kind
    /// The path(s) from entry to exit — **one chain per exit** (two for a fork).
    /// A chain is an ordered list of segments walked in sequence, so a single
    /// piece can bend twice: an S-chicane is `[.arc(L), .arc(R)]`, a lane jog
    /// `[.arc(L, 90°), .arc(R, 90°)]`. Most pieces are a one-element chain.
    public var paths: [[Segment]]
    /// Continuous **height** change across this piece (ground = 0, deck = 1):
    /// a ramp-up is +1, ramp-down −1, everything flat 0. There is no discrete
    /// layer — collision and rendering both derive from height. Height rises
    /// with smoothstep easing across the piece (see `PlacedPiece.height`).
    public var heightDelta: Double
    /// A launching ramp / jump throws the car into flight.
    public var launches: Bool

    public init(
        id: PieceID, kind: Kind = .road, paths: [[Segment]],
        heightDelta: Double = 0, launches: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.paths = paths
        self.heightDelta = heightDelta
        self.launches = launches
    }
}

extension Array where Element == Piece.Segment {
    /// The exit pose reached by walking this whole chain from `entry` — exact.
    /// An empty chain is a no-op (the entry pose itself).
    public func exit(from entry: PiecePose) -> PiecePose {
        reduce(entry) { pose, segment in segment.exit(from: pose) }
    }

    /// The pose at the start of each segment in the chain, in order — what a
    /// renderer needs to lay the segments end to end.
    public func segmentEntries(from entry: PiecePose) -> [PiecePose] {
        var pose = entry
        var poses: [PiecePose] = []
        for segment in self {
            poses.append(pose)
            pose = segment.exit(from: pose)
        }
        return poses
    }
}

extension Piece.Segment {
    /// The exit pose reached by walking this segment from `entry` — exact.
    public func exit(from entry: PiecePose) -> PiecePose {
        switch self {
        case .straight(let length):
            return entry.advanced(by: length)
        case .arc(let radius, let eighths, let left):
            return Self.arcExit(from: entry, radius: radius, eighths: eighths, left: left)
        }
    }

    /// Arc endpoint, kept exact. The center sits `radius` to the entry's side
    /// (left for a left turn); the exit sits `radius` from the center along
    /// the radial after it sweeps `eighths` × 45°, with the heading turning to
    /// match. Every offset is an integer multiple of a heading unit step, so
    /// the result stays in the ring — exact.
    ///
    /// Sanity (left, east entry, r, 90° = 2 eighths): center = (0, r), exit =
    /// (r, r) heading north.
    private static func arcExit(
        from entry: PiecePose, radius: Int, eighths: Int, left: Bool
    ) -> PiecePose {
        let toCenter = left ? entry.heading.turnedLeft(2) : entry.heading.turnedRight(2)
        let center = entry.position + toCenter.unitStep * radius
        // Radial center→entry is the opposite of center-direction; it sweeps
        // in the turn direction by `eighths`.
        let radialToEntry = toCenter.reversed
        let radialToExit =
            left ? radialToEntry.turnedLeft(eighths) : radialToEntry.turnedRight(eighths)
        let exitPos = center + radialToExit.unitStep * radius
        let exitHeading =
            left ? entry.heading.turnedLeft(eighths) : entry.heading.turnedRight(eighths)
        return PiecePose(position: exitPos, heading: exitHeading)
    }
}
