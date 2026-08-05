import Foundation

/// **Stepping a trailing warp's drop** — the pure layout edit behind the editor's
/// down/up arrows.
///
/// A warp has no length, so there is nothing to *place*: an author cannot position
/// a thing that occupies nowhere. The arrows maintain one instead, which is also
/// what keeps the layout canonical — two adjacent warps and one twice-as-deep warp
/// describe the same road, so only the single form is ever stored.
///
/// Lives in SkidCore rather than beside the editor's other append actions because
/// it is a pure function of the layout, and the interesting cases (seeding,
/// deepening, removal at zero, the floor) are worth testing without a UI.
extension TrackLayout {
    /// One step of drop, the same half-level quantum pitch uses.
    public static let warpStep = Track.levelHeight / 2

    /// Whether this layout ends in a warp — the one the arrows act on.
    public var endsInWarp: Bool { pieces.last == PieceCatalog.ID.warp }

    /// A copy with the trailing warp one step **deeper**, appending a warp if there
    /// isn't one. Never refuses: the walk clamps a too-deep warp to the world's
    /// floor, so an over-deep layout is still drivable rather than invalid.
    public func warpedDeeper() -> TrackLayout {
        var copy = self
        if endsInWarp {
            let last = copy.pieces.count - 1
            copy.warpDrops[last] = copy.warpDrop(at: last) - Self.warpStep
        } else {
            copy.pieces.append(PieceCatalog.ID.warp)
            copy.warpDrops[copy.pieces.count - 1] = -Self.warpStep
        }
        return copy
    }

    /// A copy with the trailing warp one step **shallower**, removing it once the
    /// drop reaches zero — a warp that drops nothing is not a feature, it is a
    /// leftover, and leaving it would make two spellings of one track.
    ///
    /// Returns nil when there is no warp to shallow, so the caller can disable the
    /// arrow rather than offer a no-op.
    public func warpedShallower() -> TrackLayout? {
        guard endsInWarp else { return nil }
        var copy = self
        let last = copy.pieces.count - 1
        let shallower = copy.warpDrop(at: last) + Self.warpStep
        if shallower >= 0 {
            copy.remove(at: last)
        } else {
            copy.warpDrops[last] = shallower
        }
        return copy
    }
}
