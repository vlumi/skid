import Foundation

/// Live-position ranking — reads sim state, never feeds back into it.
extension Race {
    /// How far a car is around the course, as a monotonic score: gates
    /// crossed so far, plus a within-gate fraction (0…1) toward the next gate
    /// so cars between the same two gates still order by who's closer. Used
    /// only to rank live positions — never fed back into the sim.
    ///
    /// "Closer" is measured ALONG THE ROAD (`Track.arcPosition`), not as the
    /// crow flies. Straight-line distance inverted positions on any track
    /// that curls back on itself: a car entering a clover loop sat
    /// geometrically nearer the gate beyond it than the leader rounding the
    /// loop's head, so the trailing car ranked ahead — and the HUD's debounce
    /// carried the wrong order onto the following straight.
    public func raceProgress(of car: Car) -> Double {
        let gateCount = track.gates.count
        guard gateCount > 0 else { return 0 }
        let crossed = car.progress.lap * gateCount + car.progress.nextGate
        let next = track.gates[car.progress.nextGate % gateCount]
        let mid = (next.a + next.b) * 0.5
        let length = track.centerlineLength
        var ahead =
            track.arcPosition(of: mid, preferHeight: next.height)
            - track.arcPosition(of: car.state.position, preferHeight: car.state.height)
        if ahead < 0 { ahead += length }
        // Fraction toward the next gate: closer = larger, capped to [0,1) so
        // it can never bump the crossed-gate count.
        let span = max(1, length / Double(gateCount))
        let toward = max(0, 1 - ahead / span)
        return Double(crossed) + min(0.999, toward)
    }

    /// Car indices ranked best-first for live standings (P1 = index 0 of the
    /// result). Finished cars lead, ordered by finish time; the rest by how
    /// far around they are, then distance to the next gate. Deterministic off
    /// sim state; ties break by car index so the order is stable. Meaningful
    /// only in a lap race (time trial has no field to rank).
    public var standings: [Int] {
        cars.indices.sorted { lhs, rhs in
            let a = cars[lhs]
            let b = cars[rhs]
            switch (a.progress.finishedAt, b.progress.finishedAt) {
            case (let fa?, let fb?): return fa != fb ? fa < fb : lhs < rhs
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                let pa = raceProgress(of: a)
                let pb = raceProgress(of: b)
                return pa != pb ? pa > pb : lhs < rhs
            }
        }
    }
}
