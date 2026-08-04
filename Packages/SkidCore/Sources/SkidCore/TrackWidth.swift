import Foundation

/// How wide the road is — which depends on how high it is.
extension Track {
    /// **How far the asphalt reaches from its centerline at `height`.**
    ///
    /// The ribbon is drawn wider as it rises (the fake-perspective `Elevation`
    /// scaling), and the model agrees with what it draws: a band of painted asphalt
    /// the sim called grass cost a car its grip on road it could plainly see.
    ///
    /// The rails follow this too — see `PieceCompilerWalls.deckRails`. They used to
    /// sit at a flat `width / 2` while grip scaled, which put the two in direct
    /// contradiction: a gap of `12 × height` units, unnoticed at the deck but 36
    /// units at height 3, where it reads as a transparent wall well inside the
    /// visible road ("the car doesn't reach the walls on level 3, but hits a
    /// transparent wall before it").
    public func halfWidth(atHeight height: Double) -> Double {
        width / 2 * Elevation.scale(atHeight: height)
    }

    /// **How far the road's whole visual FOOTPRINT reaches** at `height`: the
    /// asphalt, plus the kerb/rail band that straddles its edge.
    ///
    /// Distinct from `halfWidth`, which is the drivable asphalt. An elevated
    /// road's rails stand on its edge and hide the ground under them exactly
    /// as the asphalt does, so anything reasoning about what the road COVERS
    /// (the under-deck window) needs this, while anything reasoning about what
    /// a car can DRIVE on needs `halfWidth`.
    public func footprintHalfWidth(atHeight height: Double) -> Double {
        halfWidth(atHeight: height) + Double(PieceCatalog.kerbBand)
    }
}
