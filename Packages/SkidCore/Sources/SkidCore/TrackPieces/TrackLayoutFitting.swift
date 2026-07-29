import Foundation

/// Where a fitting piece lands. See `Fitter` for why its shape is float while its
/// exit stays exact.
extension TrackLayout {
    /// The inlet a fitter placed at `entry` closes onto: the nearest one it could
    /// plausibly reach, since a fitter's whole job is to bridge a gap no exact
    /// piece can. Heading must match — the piece leaves on the heading it entered,
    /// so only an inlet facing the same way is reachable.
    func fitterTarget(
        from entry: PiecePose, inlets: [(pose: PiecePose, height: Double)]
    ) -> PiecePose? {
        let start = entry.position.vec2
        return
            inlets
            .filter { $0.pose.heading == entry.heading }
            .min {
                start.distance(to: $0.pose.position.vec2)
                    < start.distance(to: $1.pose.position.vec2)
            }?
            .pose
    }
}
