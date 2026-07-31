import Foundation

/// **Editing a layout: one API, one place that remaps.**
///
/// Three things are keyed to piece indices — `gateSeams` (seam *i* is piece *i*'s
/// entry port, so a seam index IS a piece index), `fitters`, and the parallel
/// `pitches` array. Every insert, removal and rotation must move all three
/// together. Done at each call site instead, each editing operation grows its own
/// off-by-one; so `pieces` is never edited directly outside this file, and every
/// edit flows through `insert`/`remove`/`rotate`.
///
/// The contract these keep is **identity, not index**: keyed data stays with the
/// PIECE it described, wherever that piece ends up.
///
/// What they deliberately do NOT do is judge the result. A removal can strand a
/// fitter, open a ring, or leave a track under-gated — all of which the validator
/// reports and the editor surfaces. Mutation stays mechanical; legality is
/// `TrackValidator`'s job, re-judged from scratch after every edit.
extension TrackLayout {
    /// Insert a piece at `index`, shifting everything from there on — pitches,
    /// gate seams and fitters alike — one place later.
    ///
    /// Geometry is not preserved: inserting mid-ring re-walks everything after
    /// the cut, which is exactly the "slides the whole tail" behaviour the editor
    /// does not offer mid-chain. It is the primitive that append and prepend are
    /// built from.
    public mutating func insert(_ id: PieceID, pitch: Pitch = .flat, at index: Int) {
        precondition(
            (0...pieces.count).contains(index), "insert index \(index) out of range")
        pieces.insert(id, at: index)
        var padded = paddedPitches(count: pieces.count - 1)
        padded.insert(pitch, at: index)
        pitches = Self.trimmedPitches(padded)
        gateSeams = gateSeams.map { $0 >= index ? $0 + 1 : $0 }.sorted()
        let shift = { (key: Int) in key >= index ? key + 1 : key }
        fitters = remapped(fitters, by: shift)
        decals = remapped(decals, by: shift)
    }

    /// Remove the piece at `index`, pulling everything after it back one place.
    ///
    /// Whatever was keyed to the victim goes with it: its gate seam and its
    /// fitter are dropped rather than silently re-pointed at the neighbour that
    /// takes its index.
    public mutating func remove(at index: Int) {
        precondition(pieces.indices.contains(index), "remove index \(index) out of range")
        pieces.remove(at: index)
        var padded = paddedPitches(count: pieces.count + 1)
        padded.remove(at: index)
        pitches = Self.trimmedPitches(padded)
        gateSeams = gateSeams.compactMap { $0 == index ? nil : ($0 > index ? $0 - 1 : $0) }
            .sorted()
        let pullBack = { (key: Int) in key > index ? key - 1 : key }
        fitters = remapped(fitters.filter { $0.key != index }, by: pullBack)
        decals = remapped(decals.filter { $0.key != index }, by: pullBack)
    }

    /// **Re-spell a closed ring to begin at `index`.** The same ring, written from
    /// a different piece — so the road does not move.
    ///
    /// That last part is what makes ring deletion nearly free (rotate the victim
    /// to the end, pop it) and it holds only because `origin` moves too: origin
    /// describes piece 0, so rotating the list without it would slide the whole
    /// track. The new origin is the new first piece's entry pose and height,
    /// taken from the walk — already exact, so nothing drifts.
    ///
    /// Only meaningful on a **closed** ring. On an open chain the two ends are not
    /// interchangeable (rotating would splice the tail onto the head), so this
    /// leaves it untouched, as does `normalized()`.
    public mutating func rotate(to index: Int) {
        guard index != 0, pieces.indices.contains(index) else { return }
        let walk = self.walk()
        guard walk.openEnds.isEmpty, walk.failure == nil,
            walk.placed.indices.contains(index)
        else { return }

        let count = pieces.count
        pieces = Array(pieces[index...] + pieces[..<index])
        let padded = paddedPitches(count: count)
        pitches = Self.trimmedPitches(Array(padded[index...] + padded[..<index]))
        gateSeams = gateSeams.map { ($0 - index + count) % count }.sorted()
        let rotate = { (key: Int) in (key - index + count) % count }
        fitters = remapped(fitters, by: rotate)
        decals = remapped(decals, by: rotate)
        // The walk now starts at the new first piece, so the origin is that
        // piece's entry — its pose and its height.
        origin = walk.placed[index].entry
        originHeight = walk.placed[index].entryHeight
    }

    /// `pitches` padded to `count` with flats, so index arithmetic cannot
    /// silently re-associate entries. The array is stored trimmed (trailing flats
    /// dropped, so equal layouts have one representation) and every operation
    /// here pads, edits, then re-trims.
    private func paddedPitches(count: Int) -> [Pitch] {
        pitches + Array(repeating: .flat, count: max(0, count - pitches.count))
    }

    /// Index-keyed entries moved by `move`, which is total: every surviving entry
    /// lands somewhere, and two never collide (every remap here is an
    /// order-preserving bijection on the surviving indices).
    private func remapped<Value>(_ table: [Int: Value], by move: (Int) -> Int)
        -> [Int: Value]
    {
        Dictionary(uniqueKeysWithValues: table.map { (move($0.key), $0.value) })
    }
}
