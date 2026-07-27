import Foundation

/// The level vocabulary: every question about which storey a height belongs to,
/// asked through one definition.
///
/// "There are exactly two levels" used to be baked in as scattered idioms —
/// `height > 0.5` for who gets rails and which ramp a button offers,
/// `Int(height.rounded())` for search dedup, hardcoded `-0.001…1.001` bounds —
/// eleven sites across two targets, each of which would have misclassified a
/// tunnel at −1 in its own way (no rails for tunnel pieces, a search that can
/// never climb out, …). Adding a level now means changing `lowestLevel`, not
/// hunting comparisons.
extension Track {
    /// Which storey a height belongs to — the nearest whole level.
    public static func level(of height: Double) -> Int {
        Int((height / levelHeight).rounded())
    }

    /// Off the ground storey — the heights that carry structure (rails, gates)
    /// and draw differently. A future tunnel at −1 is off-ground too.
    public static func isOffGround(_ height: Double) -> Bool {
        level(of: height) != 0
    }

    /// The storeys that exist: ground and one deck. Tunnels lower the floor to
    /// −1 — HERE, not in whatever code clamps or searches heights.
    public static let lowestLevel = 0
    public static let highestLevel = 1

    /// Whether a height is inside the world's storeys, with a hair of slack
    /// for heights accumulated as sums of piece deltas.
    public static func withinLevels(_ height: Double) -> Bool {
        height >= Double(lowestLevel) * levelHeight - 0.001
            && height <= Double(highestLevel) * levelHeight + 0.001
    }

    /// The vertical gap beyond which two stretches of road belong to different
    /// levels — half a storey. (Used against solidity-interval gaps, which is
    /// why it's a distance, not a predicate on two heights.)
    public static let levelSeparation = levelHeight / 2
}
