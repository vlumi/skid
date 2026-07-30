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
    /// Choosing the anchor is all this does — `rotate(to:)` does the moving, and
    /// is the only place index-keyed data is remapped (see `TrackLayoutMutate`).
    /// It declines on an open chain or a broken walk, so those cases come back
    /// unchanged without a guard here.
    public func normalized() -> TrackLayout {
        guard let anchor = pieces.firstIndex(of: PieceCatalog.startPieceID) else { return self }
        var rotated = self
        rotated.rotate(to: anchor)
        return rotated
    }
}
