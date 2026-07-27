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
    /// The gap between one level and the next. Ground is 0 and the bridge deck is
    /// 1, so a level is one unit tall; everything below is derived from this rather
    /// than picked.
    public static let levelHeight = 1.0

    /// A hair, for comparing two heights that should be equal. Float noise only —
    /// nothing physical.
    ///
    /// This replaced a 0.35 "tolerance" I invented and then justified after the
    /// fact. It was doing four unrelated jobs at once and was far too generous for
    /// most of them, which caused a run of bugs: a car at height 0 counted as
    /// standing on a ramp 0.22 above it, and a wall at 0.8 blocked a car at 1.15.
    /// Each job now names the scale it actually needs — this one, `surfaceTolerance`
    /// for standing on a road, `reachTolerance` where a car's own size matters, and
    /// no tolerance at all for a wall's top edge.
    public static let heightEpsilon = 0.001

    /// How far apart two things can be in height and still interact physically —
    /// roughly a car's own vertical presence.
    ///
    /// Needed where the question isn't "same level?" but "close enough to touch or
    /// count": two cars colliding, or a car crossing a checkpoint gate. A car
    /// part-way up a ramp must still be able to cross a gate near the top of it,
    /// and must not phase through a car on the deck beside it, so this can't shrink
    /// to an epsilon. A fifth of a level keeps ground and deck firmly distinct.
    public static let reachTolerance = levelHeight / 5

    /// How closely a car's height must match a stretch of road to be standing
    /// **on** it. Much tighter than `heightTolerance`, and deliberately so.
    ///
    /// Derived from the sim: a climbing car's height moves at most
    /// `Race.maxHeightChangePerTick` per tick, so a car genuinely driving a slope
    /// is always within about one tick's climb of it. A shade over that keeps hold
    /// of the road under the car and nothing else.
    ///
    /// These were the same number, and that single fact produced a family of
    /// bugs. At 0.35 a car at height 0 counted as standing on a ramp that was
    /// already 0.22 above it — measured as "asphalt / on road" from 50 units away
    /// while the car was in fact underneath the slope. It got asphalt grip there,
    /// and could then take the ramp's height and ride up onto the bridge from the
    /// grass. Being *on* a surface is a much stricter question than being *at* a
    /// level, so it gets its own, tighter answer: a shade over one tick's climb,
    /// so a car driving a ramp keeps hold of it and nothing else does.
    public static let surfaceTolerance = 0.12  // ≈1.5 ticks of climb

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
