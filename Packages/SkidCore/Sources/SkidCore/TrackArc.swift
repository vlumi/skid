import Foundation

extension Track {
    /// **Where along the lap a point is**: cumulative distance along the
    /// centerline loop, from point 0 to the closest point on it. The route's
    /// own odometer — unlike straight-line distance, it is monotone along the
    /// road, which is what makes it safe to RANK cars by (a track that curls
    /// back on itself puts a trailing car geometrically closer to the gate
    /// ahead than the leader rounding the loop's head).
    ///
    /// `preferHeight` anchors a bridge crossing to the caller's own stretch,
    /// exactly as in `height(at:)`.
    public func arcPosition(
        of p: Vec2, preferHeight: Double? = nil, preferHeading: Double? = nil
    ) -> Double {
        guard centerline.count > 1 else { return 0 }
        let (segment, t) = closestCenterlinePoint(
            to: p, preferHeight: preferHeight, preferHeading: preferHeading)
        var arc = 0.0
        for i in 0..<segment {
            arc += centerline[i].distance(to: centerline[i + 1])
        }
        let a = centerline[segment]
        let b = centerline[(segment + 1) % centerline.count]
        return arc + a.distance(to: b) * t
    }
}
