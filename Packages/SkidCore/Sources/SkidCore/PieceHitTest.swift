import Foundation

/// **Which piece a tap means**, when the map is a 2D projection of a stack.
///
/// Pure geometry, in SkidCore rather than the editor view, because it is the kind of
/// thing that needs testing: on a track climbing three storeys several pieces lie
/// under every finger, and which one wins is a decision with device-reported
/// consequences.
extension WalkResult {
    /// The piece nearest `point` in WORLD coordinates, within its own drawn road
    /// width. Nil if the tap missed the road.
    ///
    /// Nearest-CENTERLINE rather than a bounding box, because pieces overlap at
    /// crossings and a box would claim taps on the road running under it.
    ///
    /// **The reach follows the road's drawn width**, which grows with height. A flat
    /// `width / 2` made a raised piece harder to hit than it looks — the asphalt under
    /// your finger reaches 20% further per storey than the tap was accepted. Same
    /// class as the rail band and gate span that were mis-sized the same way.
    ///
    /// **Ties break by height, topmost first.** On a stack the centerlines can be a
    /// hair apart, and "nearest" then picks arbitrarily between storeys; the piece
    /// drawn on top is the one being pointed at. This matches how gate seams already
    /// resolve coincident bars.
    ///
    /// `onlyLevel` restricts the test to one storey, which is the only way to reach a
    /// piece with others stacked over it.
    public func piece(
        nearWorld point: Vec2, tolerance: Double = 0, onlyLevel: Int? = nil
    ) -> Int? {
        /// The best candidate so far. A named type rather than a tuple, so the
        /// tie-break below reads as what it is.
        struct Candidate {
            var index: Int
            var distance: Double
            var height: Double
        }
        var best: Candidate?
        for (index, placed) in placed.enumerated() {
            let top = max(placed.entryHeight, placed.exitHeight)
            if let onlyLevel, Track.level(of: top) != onlyLevel { continue }
            let samples = placed.centerlineSamples(degreesPerSample: 12)
            guard samples.count > 1 else { continue }
            let reach =
                Double(PieceCatalog.width) / 2 * Elevation.scale(atHeight: top) + tolerance
            for step in 1..<samples.count {
                let distance = point.distance(toSegment: samples[step - 1], samples[step])
                guard distance <= reach else { continue }
                guard let current = best else {
                    best = Candidate(index: index, distance: distance, height: top)
                    continue
                }
                // Within a hair the distances cannot choose, so height does. Beyond
                // that, nearest still wins — a clearly closer piece is the one meant,
                // whatever its storey.
                if abs(distance - current.distance) < 1 {
                    if top > current.height {
                        best = Candidate(index: index, distance: distance, height: top)
                    }
                } else if distance < current.distance {
                    best = Candidate(index: index, distance: distance, height: top)
                }
            }
        }
        return best?.index
    }
}
