import Foundation

/// A track as the piece model stores it: an ordered piece-id list, an origin
/// pose (the start line, on the fixed canvas), the gate seam indices, and a
/// theme. This is exactly what the share code carries. Geometry is never
/// stored — it derives from walking the list.
public struct TrackLayout: Equatable, Sendable {
    public enum Theme: Int, Equatable, Sendable, Codable {
        case normal = 0, snow = 1, sand = 2
    }

    /// Pieces in ring order. The start-grid piece appears exactly once.
    public var pieces: [PieceID]
    /// Where piece 0 begins — the start line's pose on the canvas.
    public var origin: PiecePose
    /// Seam indices that are checkpoint gates (0 = the start/finish, always).
    public var gateSeams: [Int]
    public var theme: Theme

    public init(
        pieces: [PieceID], origin: PiecePose = .origin,
        gateSeams: [Int] = [0], theme: Theme = .normal
    ) {
        self.pieces = pieces
        self.origin = origin
        self.gateSeams = gateSeams
        self.theme = theme
    }
}

/// A piece placed by the walk: which catalog piece, the entry pose, and the
/// exit pose(s) (two for a fork). The seam *before* this piece is `entrySeam`.
public struct PlacedPiece: Equatable, Sendable {
    public var id: PieceID
    public var piece: Piece
    public var entry: PiecePose
    public var exits: [PiecePose]
    /// Layer at entry (the walk's running layer before this piece).
    public var entryLayer: Int
    /// Seam index at this piece's entry port.
    public var entrySeam: Int

    public init(
        id: PieceID, piece: Piece, entry: PiecePose, exits: [PiecePose],
        entryLayer: Int, entrySeam: Int
    ) {
        self.id = id
        self.piece = piece
        self.entry = entry
        self.exits = exits
        self.entryLayer = entryLayer
        self.entrySeam = entrySeam
    }

    /// World-space centerline samples for one of this piece's paths, arcs
    /// densified to ~`degreesPerSample`. Shared by the compiler (building the
    /// runtime centerline) and the editor (drawing a partial, not-yet-closed
    /// layout) so both draw identical geometry. Includes both endpoints.
    public func centerlineSamples(path pathIndex: Int = 0, degreesPerSample: Double = 6)
        -> [Vec2]
    {
        guard pathIndex < piece.paths.count else { return [entry.position.vec2] }
        switch piece.paths[pathIndex] {
        case .straight:
            return [entry.position.vec2, exits[pathIndex].position.vec2]
        case .arc(let radius, let eighths, _):
            let sweepDeg = Double(eighths) * 45
            let steps = max(1, Int((sweepDeg / degreesPerSample).rounded(.up)))
            let start = entry.position.vec2
            let left = exits[pathIndex].heading.step == Heading(entry.heading.step + eighths).step
            let toCentre = entry.heading.radians + (left ? .pi / 2 : -.pi / 2)
            let centre = start + Vec2(angle: toCentre) * Double(radius)
            let startAngle = atan2(start.y - centre.y, start.x - centre.x)
            let sweep = (left ? 1.0 : -1.0) * Double(eighths) * .pi / 4
            return (0...steps).map { k in
                let a = startAngle + sweep * Double(k) / Double(steps)
                return centre + Vec2(angle: a) * Double(radius)
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
        var inlets: [(pose: PiecePose, layer: Int)] = [(origin, 0)]
        // Loose ends still to be extended (LIFO stack). Start at the origin.
        var ends: [(pose: PiecePose, layer: Int)] = [(origin, 0)]
        var seam = 0

        for id in pieces {
            guard let piece = PieceCatalog.piece(id) else {
                return WalkResult(
                    placed: placed, openEnds: ends.map(\.pose), failure: .unknownPiece(id))
            }
            // Continue the current loose end (LIFO — a fork's branch is
            // finished before returning to the trunk's pushed exit).
            guard let current = ends.popLast() else { break }  // stranded piece
            let entry = current.pose
            let entryLayer = current.layer
            let exits = piece.paths.map { $0.exit(from: entry) }
            placed.append(
                PlacedPiece(
                    id: id, piece: piece, entry: entry, exits: exits,
                    entryLayer: entryLayer, entrySeam: seam))
            seam += 1

            let exitLayer = entryLayer + piece.layerDelta
            // A fork's SECOND+ exits become both new loose ends AND inlets
            // (a later branch can rejoin them); the FIRST exit is the one we
            // continue next. Auto-mate each exit that lands on an existing
            // inlet instead of pushing it.
            for (k, exitPose) in exits.enumerated() {
                if let hit = inlets.firstIndex(where: {
                    mate(exitPose, $0.pose) && exitLayer == $0.layer
                }) {
                    inlets.remove(at: hit)  // closed this joint
                } else {
                    ends.append((exitPose, exitLayer))
                    if k > 0 { inlets.append((exitPose, exitLayer)) }
                }
            }
        }

        return WalkResult(placed: placed, openEnds: ends.map(\.pose), failure: nil)
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
