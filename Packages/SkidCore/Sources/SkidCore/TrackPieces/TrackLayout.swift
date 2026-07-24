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
    /// Continuous **height** at this piece's entry (0 = ground, 1 = deck).
    /// The exit height is `entryHeight + piece.heightDelta`.
    public var entryHeight: Double
    /// Seam index at this piece's entry port.
    public var entrySeam: Int

    public init(
        id: PieceID, piece: Piece, entry: PiecePose, exits: [PiecePose],
        entryHeight: Double, entrySeam: Int
    ) {
        self.id = id
        self.piece = piece
        self.entry = entry
        self.exits = exits
        self.entryHeight = entryHeight
        self.entrySeam = entrySeam
    }

    /// Height at this piece's exit.
    public var exitHeight: Double { entryHeight + piece.heightDelta }

    /// The discrete surface a car on this piece collides with — derived from
    /// height, not stored. Rounds so a flat deck piece (height 1) is layer 1,
    /// ground (0) is layer 0; a ramp mid-climb rounds to whichever it's nearer.
    public var layer: Int { Int(exitHeight.rounded()) }

    /// Height at fraction `f` (0…1) along this piece, eased with **smoothstep**
    /// so a ramp meets the ground and deck smoothly rather than with hard
    /// creases. Flat pieces stay constant; the whole visual scale (road width,
    /// car size, wedge) reads off this.
    public func height(atFraction f: Double) -> Double {
        guard piece.heightDelta != 0 else { return entryHeight }
        let x = min(1, max(0, f))
        let eased = x * x * (3 - 2 * x)  // smoothstep
        return entryHeight + piece.heightDelta * eased
    }

    /// World-space centerline samples paired with the **height** at each one
    /// (eased along the piece). Renderers use this to vary road width / car
    /// scale continuously with elevation — a ramp widens as it climbs, no
    /// special-casing. First path only (the driven trunk).
    public func heightedSamples(degreesPerSample: Double = 6) -> [(point: Vec2, height: Double)] {
        let pts = centerlineSamples(degreesPerSample: degreesPerSample)
        guard pts.count > 1 else { return pts.map { ($0, entryHeight) } }
        let last = Double(pts.count - 1)
        return pts.enumerated().map { i, p in (p, height(atFraction: Double(i) / last)) }
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
        var inlets: [(pose: PiecePose, height: Double)] = [(origin, 0)]
        // Loose ends still to be extended (LIFO stack). Start at the origin.
        var ends: [(pose: PiecePose, height: Double)] = [(origin, 0)]
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
            let entryHeight = current.height
            let exits = piece.paths.map { $0.exit(from: entry) }
            placed.append(
                PlacedPiece(
                    id: id, piece: piece, entry: entry, exits: exits,
                    entryHeight: entryHeight, entrySeam: seam))
            seam += 1

            let exitHeight = entryHeight + piece.heightDelta
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

    /// A loose end mates an inlet when their poses are **identical** — same
    /// position and same heading. The walk is forward-driven: an inlet stores
    /// the direction traffic flows *into* the joint (the origin faces the way
    /// piece 0 drives away; a fork branch-exit faces the way it drives on), so
    /// a returning end closes by flowing in the *same* direction, not head-on.
    private func mate(_ end: PiecePose, _ inlet: PiecePose) -> Bool {
        end == inlet
    }
}
