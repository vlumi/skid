import Foundation

/// **One track, one code.** A closed ring can be spelled starting from any of its
/// pieces; encoding picks one spelling so a share code is an identity.
extension TrackLayout {
    /// **The same ring, written from its canonical starting piece.**
    ///
    /// A closed ring can be spelled starting from any of its pieces, and every
    /// spelling is the same track — so a share code would not be an identity
    /// unless one spelling is chosen. This rotates the list to begin at the
    /// start line, carrying `origin`/`originHeight` to whatever piece becomes
    /// first (they describe piece 0, so rotating without them moves the track)
    /// and shifting `gateSeams` and `pitches` by the same offset.
    ///
    /// An OPEN chain is returned unchanged: its first piece is where the author
    /// started building and its two ends are not interchangeable, so there is
    /// nothing canonical to rotate to.
    ///
    /// (When the fitting piece exists it becomes the anchor instead, since the
    /// walk must grow both chains outward from it — see
    /// docs/flexible-tracks-plan.md.)
    public func normalized() -> TrackLayout {
        let walk = self.walk()
        // Only a closed ring may be rotated.
        guard walk.openEnds.isEmpty, walk.failure == nil else { return self }
        guard
            let anchor = pieces.firstIndex(of: PieceCatalog.startPieceID),
            anchor != 0
        else { return self }
        guard walk.placed.indices.contains(anchor) else { return self }

        let count = pieces.count
        var rotated = self
        rotated.pieces = Array(pieces[anchor...] + pieces[..<anchor])
        // Pitches run parallel to pieces but may be short; pad before rotating
        // so the rotation cannot silently re-associate them.
        var padded = pitches
        while padded.count < count { padded.append(.flat) }
        rotated.pitches = Array(padded[anchor...] + padded[..<anchor])
        rotated.gateSeams = gateSeams.map { ($0 - anchor + count) % count }.sorted()
        // Fitters are keyed by piece index, so they rotate with the pieces.
        rotated.fitters = Dictionary(
            uniqueKeysWithValues: fitters.map { (($0.key - anchor + count) % count, $0.value) })
        // The walk starts at the new first piece, so the origin is that piece's
        // entry — its pose and its height.
        rotated.origin = walk.placed[anchor].entry
        rotated.originHeight = walk.placed[anchor].entryHeight
        return rotated
    }
}
