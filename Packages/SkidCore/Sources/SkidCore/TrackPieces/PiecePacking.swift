import Foundation

/// Packs a primitive piece list into **compounds** for encoding, and unpacks it
/// again on decode.
///
/// A layout stores primitives, which is what gives a hairpin interior seams to hang
/// a checkpoint on. But primitives are repetitive by nature — a hairpin is four
/// identical 45s — so writing them out one id at a time wastes bytes on exactly the
/// shapes people use most. Packing them back into compounds fixes that: a compound
/// id *is* the run, costing one byte where run-length encoding would cost two (id +
/// count).
///
/// Measured on the real built-ins, pieces section only: 16 B → 7 B, 15 B → 5 B,
/// 21 B → 11 B. Run-length managed only 19–40% on the same tracks.
public enum PiecePacking {
    /// Pack primitives into the fewest compound ids.
    ///
    /// **Greedy longest-match, and that's what makes it canonical.** At each
    /// position it takes the longest compound that matches, so a given primitive
    /// list packs exactly one way. That matters because a share code doubles as a
    /// track's identity: if the same track could encode two ways, two codes would
    /// name one track and dedup would break.
    public static func pack(_ primitives: [(id: PieceID, pitch: Pitch)]) -> [PieceID] {
        let compounds = PieceExpansion.compoundsLongestFirst
        var out: [PieceID] = []
        var index = 0
        while index < primitives.count {
            var matched = false
            for compound in compounds {
                let run = compound.primitives
                guard index + run.count <= primitives.count else { continue }
                guard
                    zip(primitives[index..<(index + run.count)], run).allSatisfy({
                        $0.id == $1.id && $0.pitch == $1.pitch
                    })
                else { continue }
                out.append(compound.id)
                index += run.count
                matched = true
                break
            }
            if !matched {
                // A pitched primitive outside any compound has no byte form yet —
                // that arrives with the mode-switch encoding. Until then the only
                // sources of pitch are the ramp compounds, which always pack back;
                // anything else here is a programming error, and dropping the
                // pitch silently would corrupt the track.
                precondition(
                    primitives[index].pitch == .flat,
                    "pitched primitive outside a compound is not encodable yet")
                out.append(primitives[index].id)
                index += 1
            }
        }
        return out
    }

    /// Unpack encoded ids back to primitives, bounded as it goes.
    ///
    /// Nil when the expansion would exceed `limit` — a short code full of compounds
    /// must be refused before it allocates, not expanded and then measured.
    public static func unpack(_ ids: [PieceID], limit: Int) -> [(id: PieceID, pitch: Pitch)]? {
        PieceExpansion.expand(all: ids, limit: limit)
    }
}
