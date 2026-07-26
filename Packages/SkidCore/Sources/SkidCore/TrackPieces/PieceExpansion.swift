import Foundation

/// How a **compound** piece id expands into the primitives it is made of.
///
/// The piece model has two levels, deliberately:
///
/// - **Primitives** are what a layout stores and the compiler walks: a short
///   straight, and 45° corners at each radius. Everything else composes from them
///   *exactly* — 2U is two shorts, a 90° is two 45s, a hairpin is four — with
///   identical end poses, since the `Coord` ring is closed under 45° rotation.
/// - **Compounds** are a convenience that exists at the edges: one tap in the
///   editor, one byte in a share code, one step in the closure search.
///
/// Keeping the layout primitive is what buys a **checkpoint at a hairpin's apex** —
/// a seam exists wherever two pieces meet, so a hairpin that *is* four pieces has
/// three interior seams to mark, where a single hairpin piece has none. That was
/// the whole point; the byte saving is a bonus.
///
/// The compound stays the canonical **encoding**, though: a compound id costs one
/// byte where run-length encoding costs two (id + count), so `[hairpin]` beats
/// `[45L, 45L, 45L, 45L]` and beats `[45L ×4]`. Measured on the real built-ins, the
/// pieces section roughly halves.
public enum PieceExpansion {
    /// The primitives a piece expands to, or `[id]` for something already
    /// primitive (or with no expansion, like the start grid and ramps).
    public static func expand(_ id: PieceID) -> [PieceID] {
        table[id] ?? [id]
    }

    /// Expand a whole piece list, bounded as it goes.
    ///
    /// The bound is checked **during** expansion, not after: a short hostile code
    /// full of compounds would otherwise allocate a long layout before anything
    /// noticed. Returns nil when the limit is exceeded, so the caller can reject
    /// the code rather than trust a truncated result.
    public static func expand(all ids: [PieceID], limit: Int) -> [PieceID]? {
        var out: [PieceID] = []
        out.reserveCapacity(ids.count)
        for id in ids {
            for primitive in expand(id) {
                guard out.count < limit else { return nil }
                out.append(primitive)
            }
        }
        return out
    }

    /// Whether an id is a primitive — something a layout may contain.
    public static func isPrimitive(_ id: PieceID) -> Bool {
        table[id] == nil
    }

    /// Compounds, longest first, for an encoder that wants the fewest bytes.
    ///
    /// Longest-first is what makes the encoding canonical: greedily taking the
    /// longest match at each position gives one byte sequence per piece list, and
    /// byte-stability is what lets a share code be an identity.
    public static var compoundsLongestFirst: [(id: PieceID, primitives: [PieceID])] {
        table.map { (id: $0.key, primitives: $0.value) }
            .sorted {
                $0.primitives.count != $1.primitives.count
                    ? $0.primitives.count > $1.primitives.count : $0.id < $1.id
            }
    }

    /// The expansion table. Everything here is verified to compose exactly — see
    /// `PieceExpansionTests`, which walks each compound and its expansion and
    /// asserts the end poses are identical, not merely close.
    private static let table: [PieceID: [PieceID]] = {
        typealias ID = PieceCatalog.ID
        var table: [PieceID: [PieceID]] = [:]

        // Straights: multiples of the short straight.
        table[ID.straight] = Array(repeating: ID.shortStraight, count: 2)
        table[ID.longStraight] = Array(repeating: ID.shortStraight, count: 4)

        // Corners: a 90° is two 45s of the same radius; a hairpin is four.
        for corner in Corner.families {
            table[corner.ninety] = Array(repeating: corner.fortyFive, count: 2)
            if let hairpin = corner.hairpin {
                table[hairpin] = Array(repeating: corner.fortyFive, count: 4)
            }
        }

        // Chicanes: 45° one way then 45° back, so the road shifts sideways and
        // leaves on its original heading. Each is its own family's 45 followed by
        // the opposite hand at the same radius.
        for corner in Corner.families {
            table[corner.chicane] = [corner.fortyFive, corner.mirrored]
        }

        // Lane jogs: 90° out and 90° back, shifting sideways a whole number of U.
        // Note these are NOT a radius family — 240 and 360 name the lateral shift,
        // and both start with a tight arc — which is exactly why they can't simply
        // follow a selected radius.
        table[ID.jog240Left] = [ID.curve90TightLeft, ID.curve90TightRight]
        table[ID.jog240Right] = [ID.curve90TightRight, ID.curve90TightLeft]
        table[ID.jog360Left] = [ID.curve90TightLeft, ID.curve90MediumRight]
        table[ID.jog360Right] = [ID.curve90TightRight, ID.curve90MediumLeft]

        // Jogs expand to 90s, which are themselves compound — flatten so every
        // value is genuinely primitive.
        for (id, primitives) in table where primitives.contains(where: { table[$0] != nil }) {
            table[id] = primitives.flatMap { table[$0] ?? [$0] }
        }
        return table
    }()
}

/// One corner family: the 45° primitive it's built from, and the compounds that
/// are runs of it.
private struct Corner {
    var fortyFive: PieceID
    /// The same radius, opposite hand — the second half of a chicane.
    var mirrored: PieceID
    var ninety: PieceID
    var chicane: PieceID
    /// Nil for sweep: there is no sweep hairpin in the catalog, by design.
    var hairpin: PieceID?

    static let families: [Corner] = {
        typealias ID = PieceCatalog.ID
        return [
            Corner(
                fortyFive: ID.curve45TightLeft, mirrored: ID.curve45TightRight,
                ninety: ID.curve90TightLeft, chicane: ID.chicaneTightLeft,
                hairpin: ID.hairpinTightLeft),
            Corner(
                fortyFive: ID.curve45TightRight, mirrored: ID.curve45TightLeft,
                ninety: ID.curve90TightRight, chicane: ID.chicaneTightRight,
                hairpin: ID.hairpinTightRight),
            Corner(
                fortyFive: ID.curve45MediumLeft, mirrored: ID.curve45MediumRight,
                ninety: ID.curve90MediumLeft, chicane: ID.chicaneMediumLeft,
                hairpin: ID.hairpinMediumLeft),
            Corner(
                fortyFive: ID.curve45MediumRight, mirrored: ID.curve45MediumLeft,
                ninety: ID.curve90MediumRight, chicane: ID.chicaneMediumRight,
                hairpin: ID.hairpinMediumRight),
            Corner(
                fortyFive: ID.curve45SweepLeft, mirrored: ID.curve45SweepRight,
                ninety: ID.curve90SweepLeft, chicane: ID.chicaneSweepLeft,
                hairpin: nil),
            Corner(
                fortyFive: ID.curve45SweepRight, mirrored: ID.curve45SweepLeft,
                ninety: ID.curve90SweepRight, chicane: ID.chicaneSweepRight,
                hairpin: nil),
        ]
    }()
}
