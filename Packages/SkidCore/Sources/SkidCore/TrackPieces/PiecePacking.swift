import Foundation

/// Packs a resolved primitive list into **compounds and mode switches** for
/// encoding, and unpacks it again on decode.
///
/// Two kinds of virtual element share the byte stream, both invisible to the
/// in-memory layout. A **compound** id is a run of primitives (one byte for a
/// whole hairpin). A **mode switch** carries state: it sets the pitch for every
/// primitive after it until the next switch, which is how a lone half-climb —
/// one pitched short with no compound to absorb it — gets a byte form. The
/// encoder is canonical about both: greedy longest-match for compounds first,
/// then a switch only where the next primitive's pitch differs from the running
/// state, and no trailing reset (state dies with the stream).
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
    /// Mode-switch ids, in the block reserved away from catalog pieces (which
    /// grow upward from 0) and decal variants (128+). One byte each.
    public static let switchPitchFlat: PieceID = 120
    public static let switchPitchUp: PieceID = 121
    public static let switchPitchDown: PieceID = 122

    /// The pitch a switch id selects, nil for anything else.
    static func switchedPitch(_ id: PieceID) -> Pitch? {
        switch id {
        case switchPitchFlat: return .flat
        case switchPitchUp: return .up
        case switchPitchDown: return .down
        default: return nil
        }
    }
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
        // The pitch state the stream is in; primitives at this pitch need no
        // switch. Compounds never touch it — their expansions carry explicit
        // pitches — so a ramp mid-stream costs the same byte it always did.
        var mode = Pitch.flat
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
                // A primitive the compounds didn't absorb: switch the running
                // pitch state if it differs, then emit the piece bare.
                if primitives[index].pitch != mode {
                    mode = primitives[index].pitch
                    out.append(switchID(for: mode))
                }
                out.append(primitives[index].id)
                index += 1
            }
        }
        return out
    }

    private static func switchID(for pitch: Pitch) -> PieceID {
        switch pitch {
        case .flat: return switchPitchFlat
        case .up: return switchPitchUp
        case .down: return switchPitchDown
        }
    }

    /// Unpack encoded ids back to resolved primitives, bounded as it goes.
    ///
    /// Nil when the expansion would exceed `limit` — a short code full of compounds
    /// must be refused before it allocates, not expanded and then measured. Mode
    /// switches consume no length: they are state, not road.
    public static func unpack(_ ids: [PieceID], limit: Int) -> [(id: PieceID, pitch: Pitch)]? {
        var out: [(id: PieceID, pitch: Pitch)] = []
        out.reserveCapacity(ids.count)
        var mode = Pitch.flat
        for id in ids {
            if let pitch = switchedPitch(id) {
                mode = pitch
                continue
            }
            for primitive in PieceExpansion.expand(id) {
                guard out.count < limit else { return nil }
                // A compound's expansion is explicit; a bare primitive takes
                // the stream's pitch state.
                let pitch = PieceExpansion.isPrimitive(id) ? mode : primitive.pitch
                out.append((primitive.id, pitch))
            }
        }
        return out
    }
}
