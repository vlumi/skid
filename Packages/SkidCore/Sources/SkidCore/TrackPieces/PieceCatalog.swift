import Foundation

/// The piece catalog: the id → `Piece` table. Ids in the one-byte range
/// (0…127) are **core geometry**; decals and other variants live at 128+ so
/// the compact range is never rationed. The registry is frozen only at the
/// format's first public release — until then ids may be reshuffled.
///
/// Numbers here (lengths, radii, width) are v1 values, expected to be tuned on
/// device once the editor renders them.
public enum PieceCatalog {
    /// The base unit **U** every length and radius is a multiple of — equal to
    /// the road width, so footprints stay unit-quantized too. Integer
    /// dimensions are automatically exact on the (a + b√2)/2 lattice, so the
    /// unit system is purely about *meshing*: whatever the author builds,
    /// mismatches are whole units, never stray fractions.
    public static let unit = 120

    /// One global road width in v1, so every port mates trivially. Width == U.
    ///
    /// This is the **grip width**: the asphalt a car drives on, and what
    /// collision and `Elevation.scale` work from. Edge decoration lives
    /// *outboard* of it (see `edgeLine` / `kerbBand`) and never eats into it.
    public static let width = unit

    /// The thin white line every road edge carries — the default look, painted
    /// just outside the grip surface. It marks the edge without pretending to
    /// be a feature.
    public static let edgeLine = unit / 20  // 6

    /// The red/white kerb band, for edges that earn one — a curve's outer edge,
    /// an apex. Wider than the plain line, and also entirely outboard: a kerb is
    /// paint, so it never narrows the road, counts as asphalt if a car touches
    /// it (no slowdown, no barrier), and grass starts only past it.
    public static let kerbBand = unit / 8  // 15

    /// The three curve radii — measured to the road **center** — on the same
    /// 1:2:4 doubling as the straights. The tight radius equals a full width,
    /// so its inner edge still sweeps a real arc (at U/2) instead of
    /// collapsing to a pivot point.
    public static let tightRadius = unit  // 120
    public static let mediumRadius = 2 * unit  // 240
    public static let sweepRadius = 4 * unit  // 480

    /// Straight lengths, the same doubling family.
    public static let shortStraight = unit  // 120
    public static let straight = 2 * unit  // 240
    public static let longStraight = 4 * unit  // 480

    /// The whole v1 catalog, keyed by id.
    public static let all: [PieceID: Piece] = {
        var c: [PieceID: Piece] = [:]
        func add(_ p: Piece) { c[p.id] = p }

        // Straights — 1U / 2U / 4U
        add(Piece(id: ID.shortStraight, paths: [[.straight(length: shortStraight)]]))
        add(Piece(id: ID.straight, paths: [[.straight(length: straight)]]))
        add(Piece(id: ID.longStraight, paths: [[.straight(length: longStraight)]]))

        // Curves: the model's `left` is a math-CCW turn, which renders CLOCKWISE
        // on screen (y-down). So a piece the PLAYER calls "left" (screen-left =
        // counter-clockwise on screen) is `left: false` here. `screenLeft`
        // names it once so the catalog reads in player terms.
        let screenLeft = false, screenRight = true
        func arc(_ r: Int, _ eighths: Int, _ left: Bool) -> Piece.Segment {
            .arc(radius: r, eighths: eighths, left: left)
        }
        /// One curve family: the same shape mirrored, at one radius.
        func addPair(_ leftID: PieceID, _ rightID: PieceID, _ shape: (Bool) -> [Piece.Segment]) {
            add(Piece(id: leftID, paths: [shape(screenLeft)]))
            add(Piece(id: rightID, paths: [shape(screenRight)]))
        }

        // 45° and 90° curves × tight/medium/sweep.
        addPair(ID.curve45TightLeft, ID.curve45TightRight) { [arc(tightRadius, 1, $0)] }
        addPair(ID.curve45MediumLeft, ID.curve45MediumRight) { [arc(mediumRadius, 1, $0)] }
        addPair(ID.curve45SweepLeft, ID.curve45SweepRight) { [arc(sweepRadius, 1, $0)] }
        addPair(ID.curve90TightLeft, ID.curve90TightRight) { [arc(tightRadius, 2, $0)] }
        addPair(ID.curve90MediumLeft, ID.curve90MediumRight) { [arc(mediumRadius, 2, $0)] }
        addPair(ID.curve90SweepLeft, ID.curve90SweepRight) { [arc(sweepRadius, 2, $0)] }

        // 180° hairpins — tight and medium only (a sweep U-turn spans 9U).
        addPair(ID.hairpinTightLeft, ID.hairpinTightRight) { [arc(tightRadius, 4, $0)] }
        addPair(ID.hairpinMediumLeft, ID.hairpinMediumRight) { [arc(mediumRadius, 4, $0)] }

        // S-chicanes: two 45° arcs chained — the road bends one way and straight
        // back, ending on the ENTRY heading, shifted sideways by r(2−√2). That
        // shift is irrational (off-grid), so a chicane closes against its
        // mirror, like every 45° piece.
        addPair(ID.chicaneTightLeft, ID.chicaneTightRight) {
            [arc(tightRadius, 1, $0), arc(tightRadius, 1, !$0)]
        }
        addPair(ID.chicaneMediumLeft, ID.chicaneMediumRight) {
            [arc(mediumRadius, 1, $0), arc(mediumRadius, 1, !$0)]
        }
        addPair(ID.chicaneSweepLeft, ID.chicaneSweepRight) {
            [arc(sweepRadius, 1, $0), arc(sweepRadius, 1, !$0)]
        }

        // Lane jogs: two 90° arcs chained — out and back to the ENTRY heading,
        // shifted sideways by r_a + r_b, a whole number of units. Unlike the
        // chicane these are fully grid-clean, which makes them the radius
        // bridges: the 240 jog re-lines a sweep corner as a medium, the 360 jog
        // as a tight. (A 120 jog would need r=60, below the tight minimum —
        // that gap is absorbed with a detour instead. Deliberate, see docs.)
        addPair(ID.jog240Left, ID.jog240Right) {
            [arc(tightRadius, 2, $0), arc(tightRadius, 2, !$0)]
        }
        addPair(ID.jog360Left, ID.jog360Right) {
            [arc(tightRadius, 2, $0), arc(mediumRadius, 2, !$0)]
        }

        // Ramps (straight 2U, height change). A bridge ramp is something you
        // DRIVE UP, so it must not launch: flagged `launches: true`, an up-ramp
        // threw the car into ballistic flight at the top, which is exactly the
        // "car jumps at the top of the ramp" that made bridges feel broken — and
        // it made reaching the deck depend on carrying enough speed. Launching is
        // what the separate `jump` piece is for.
        add(Piece(id: ID.rampUp, paths: [[.straight(length: straight)]], heightDelta: 1))
        add(Piece(id: ID.rampDown, paths: [[.straight(length: straight)]], heightDelta: -1))

        // Start grid (straight 2U; the start/finish line is at its exit).
        add(Piece(id: ID.startGrid, paths: [[.straight(length: straight)]]))

        // The fitting piece. Its `paths` are a PLACEHOLDER and are never walked:
        // the walk takes a fitter's exit from the inlet it closes onto, and its
        // real shape comes from the solved `Fitter` in the layout (see
        // `TrackLayout.fitters`). The entry exists so the piece has a catalog
        // identity — a kind, a name, a footprint for the palette — like everything
        // else. Registering it with a zero-length straight keeps anything that
        // walks the catalog blind to the special case.
        add(Piece(id: ID.fitter, paths: [[.straight(length: 0)]]))

        // Crossable straights (at-grade intersections): 1U covers a 90°
        // crossing (shared zone = one width); a diagonal crossing needs 2U.
        add(
            Piece(
                id: ID.crossingShort, kind: .crossing, paths: [[.straight(length: shortStraight)]]))
        add(Piece(id: ID.crossing, kind: .crossing, paths: [[.straight(length: straight)]]))

        // Forks: one entry, two exits (straight + branch, or symmetric).
        // Branches use the medium radius so a fork's footprint stays modest.
        // Joins are the mirrored pieces (two entries → one exit): at the model
        // level a join walks as a fork in reverse, so it carries the same path
        // shapes with `kind: .fork`; distinct ids keep the encoding directional.
        for (straightLeft, straightRight, symmetric) in [
            (ID.forkStraightLeft, ID.forkStraightRight, ID.forkSymmetric),
            (ID.joinStraightLeft, ID.joinStraightRight, ID.joinSymmetric),
        ] {
            add(
                Piece(
                    id: straightLeft, kind: .fork,
                    paths: [[.straight(length: straight)], [arc(mediumRadius, 2, screenLeft)]]))
            add(
                Piece(
                    id: straightRight, kind: .fork,
                    paths: [[.straight(length: straight)], [arc(mediumRadius, 2, screenRight)]]))
            add(
                Piece(
                    id: symmetric, kind: .fork,
                    paths: [
                        [arc(mediumRadius, 2, screenLeft)], [arc(mediumRadius, 2, screenRight)],
                    ]))
        }

        // **Gap: 1U of no road.** Chain them for a longer gap; pitch each one down
        // to descend across it. There is no `launches` flag and no launch line — a
        // car flies because it drove off a WEDGE (see `TrackLayout.walk`), which is
        // real slope becoming real vertical speed rather than an invisible trigger
        // on flat asphalt.
        add(Piece(id: ID.gap, kind: .gap, paths: [[.straight(length: shortStraight)]]))

        // The vertical warp: ZERO length, so the walk's pose is unchanged and only
        // the height moves. Registered with a zero-length straight exactly like the
        // fitter, which keeps anything that walks the catalog blind to it.
        add(Piece(id: ID.warp, kind: .warp, paths: [[.straight(length: 0)]]))

        // 128–130 decal variants: straights with a driving-direction arrow —
        // identical geometry to the plain straights, different look (two-byte
        // id range, so the compact range is never rationed).
        add(Piece(id: 128, paths: [[.straight(length: shortStraight)]]))
        add(Piece(id: 129, paths: [[.straight(length: straight)]]))
        add(Piece(id: 130, paths: [[.straight(length: longStraight)]]))

        return c
    }()

    /// **The same shape turning the other way**, or the piece itself when it has no
    /// handedness (a straight, the start line).
    ///
    /// Derived by comparing GEOMETRY, not by pairing ids: `addPair` happens to lay
    /// left and right down consecutively, but nothing enforces that, and a piece
    /// added out of order would silently mirror to the wrong shape.
    ///
    /// Needed because building BACKWARDS draws the mirror of what gets stored — a
    /// left turn drawn away from the head is a right turn to a car driving into it.
    /// See `CouchGame.editorPlace`.
    public static let mirrored: [PieceID: PieceID] = {
        var map: [PieceID: PieceID] = [:]
        for (id, piece) in all {
            guard let path = piece.paths.first else { continue }
            // No arcs, no handedness: the piece IS its own mirror. Without this an
            // id-order search matches some other straight with the same path —
            // several pieces are a plain 1U straight, so 29 "mirrored" to 31.
            let handed = path.contains { segment in
                if case .arc = segment { return true }
                return false
            }
            guard handed else {
                map[id] = id
                continue
            }
            let flipped = path.map { segment -> Piece.Segment in
                if case .arc(let radius, let eighths, let left) = segment {
                    return .arc(radius: radius, eighths: eighths, left: !left)
                }
                return segment
            }
            map[id] =
                all.first { $0.value.paths.first == flipped && $0.value.kind == piece.kind }?.key
                ?? id
        }
        return map
    }()

    /// Named ids for the pieces callers reach for by name (tests, the editor
    /// palette, the context-aware ramp button). Ids themselves stay data — the
    /// registry is frozen only at the format's first public release — so
    /// nothing outside this file should hardcode a number.
    /// Catalog ids grow upward from 0. **112–127 are reserved for the byte
    /// stream's mode switches** (`PiecePacking`) and may never name a piece;
    /// 128+ are decal variants. A test pins the reservation.
    public enum ID {
        public static let shortStraight: PieceID = 0
        public static let straight: PieceID = 1
        public static let longStraight: PieceID = 2
        /// 45° curves, screen-left / screen-right, per radius.
        public static let curve45TightLeft: PieceID = 3
        public static let curve45TightRight: PieceID = 4
        public static let curve45MediumLeft: PieceID = 5
        public static let curve45MediumRight: PieceID = 6
        public static let curve45SweepLeft: PieceID = 7
        public static let curve45SweepRight: PieceID = 8
        /// 90° curves, screen-left / screen-right, per radius.
        public static let curve90TightLeft: PieceID = 9
        public static let curve90TightRight: PieceID = 10
        public static let curve90MediumLeft: PieceID = 11
        public static let curve90MediumRight: PieceID = 12
        public static let curve90SweepLeft: PieceID = 13
        public static let curve90SweepRight: PieceID = 14
        /// 180° hairpins (tight + medium only).
        public static let hairpinTightLeft: PieceID = 15
        public static let hairpinTightRight: PieceID = 16
        public static let hairpinMediumLeft: PieceID = 17
        public static let hairpinMediumRight: PieceID = 18
        /// S-chicanes: bend one way and back, ending on the entry heading.
        public static let chicaneTightLeft: PieceID = 19
        public static let chicaneTightRight: PieceID = 20
        public static let chicaneMediumLeft: PieceID = 21
        public static let chicaneMediumRight: PieceID = 22
        public static let chicaneSweepLeft: PieceID = 23
        public static let chicaneSweepRight: PieceID = 24
        /// Lane jogs: 90° out and back, shifting sideways a whole number of U.
        public static let jog240Left: PieceID = 25
        public static let jog240Right: PieceID = 26
        public static let jog360Left: PieceID = 27
        public static let jog360Right: PieceID = 28
        public static let rampUp: PieceID = 29
        public static let rampDown: PieceID = 30
        public static let startGrid: PieceID = 31
        public static let crossingShort: PieceID = 32
        public static let crossing: PieceID = 33
        public static let forkStraightLeft: PieceID = 34
        public static let forkStraightRight: PieceID = 35
        public static let forkSymmetric: PieceID = 36
        public static let joinStraightLeft: PieceID = 37
        public static let joinStraightRight: PieceID = 38
        public static let joinSymmetric: PieceID = 39
        /// **A gap: 1U of no road at all.** Chain them for a longer gap; pitch each
        /// one down to descend across it.
        public static let gap: PieceID = 40
        /// The fitting piece — a curve-straight-curve jog whose shape is SOLVED
        /// and stored per placement, not fixed by the catalog. See `Fitter`.
        public static let fitter: PieceID = 41
        /// **A vertical warp: the road continues LOWER, at the same place.**
        ///
        /// Zero length, so it moves nothing horizontally — it only says where the
        /// next piece sits. The amount is a per-placement attribute (`warpDrop`),
        /// not a piece per depth, and it is DOWN only: nothing lifts a car, so an
        /// upward warp would be a road that teleports.
        public static let warp: PieceID = 42
    }

    /// The start-grid piece id — exactly one per track.
    public static let startPieceID: PieceID = ID.startGrid

    /// The fitting piece's id. Unlike every other piece, its geometry is not in
    /// the catalog: each placement carries its own solved shape in
    /// `TrackLayout.fitters`, because the whole point is a shape the catalog
    /// cannot express.
    public static let fitterPieceID: PieceID = ID.fitter

    public static func piece(_ id: PieceID) -> Piece? { all[id] }
}
