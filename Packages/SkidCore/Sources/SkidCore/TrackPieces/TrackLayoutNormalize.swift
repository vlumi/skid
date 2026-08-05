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
        rotated.centerOnCanvas()
        return rotated
    }

    /// **Sit the track in the middle of the canvas.** Part of normalizing, because
    /// where a track sits is not part of what it IS.
    ///
    /// Nothing downstream cares: `PieceCompiler.framed()` re-frames every compiled
    /// track to its own bounds, so the race sees the same road wherever it was built
    /// (measured: a rigid translation, identical canvas size), and `fitsCanvas`
    /// compares EXTENTS rather than position, so validation is position-invariant.
    /// The only thing the position ever changed was the share code — which is exactly
    /// the arbitrary difference normalizing exists to absorb, like the ring spelling
    /// above and the gate-seam order.
    ///
    /// There was a button for this. It could not work: whole-lattice shifts leave a
    /// residual of up to half a piece that no press can improve, so on a nearly
    /// centred track it correctly did nothing and looked broken. Doing it as part of
    /// normalizing removes the question.
    ///
    /// Shifts by whole pieces, because `origin` is an exact `Coord` and must stay one.
    mutating func centerOnCanvas() {
        let margin = Double(PieceCatalog.width) / 2
        guard let used = walk().footprint(padding: margin) else { return }
        let canvas = TrackValidator.canvas
        let unit = Double(PieceCatalog.unit)
        let steps = CoordPoint(
            Int((((canvas.x - used.width) / 2 - used.minX) / unit).rounded())
                * PieceCatalog.unit,
            Int((((canvas.y - used.height) / 2 - used.minY) / unit).rounded())
                * PieceCatalog.unit)
        guard steps != CoordPoint(0, 0) else { return }
        origin = PiecePose(position: origin.position + steps, heading: origin.heading)
    }
}
