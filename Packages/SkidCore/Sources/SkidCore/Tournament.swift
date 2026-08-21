import Foundation

/// **A series of races, scored on points.**
///
/// The one mode that gives a five-second lap a reason to be driven forty times.
/// Deliberately a plain value in `SkidCore`: the rules are arithmetic, so they
/// are testable without a screen, and the app layer only has to persist it and
/// ask it what comes next.
///
/// **Points, not cumulative time.** A couch loses interest if one spin ends the
/// series, and points forgive a bad race — the F1 table is the one people already
/// know, so nobody has to be taught the rule.
///
/// **Scored per SEAT, not per profile.** The same people sit in the same seats for
/// a series; if two of them want to share a seat as a team, that is their
/// business and the game should not have an opinion. So a seat is the competitor
/// and whoever sits there owns its points — which also means a tournament needs
/// no profiles at all, and a couch of guests can play one.
public struct Tournament: Equatable, Sendable, Codable {
    /// **F1's current table**, down to tenth. The set most people can already
    /// read, so the scoring needs no explaining; a field of four uses the first
    /// four values, which keep the same shape (25/18/15/12).
    public static let pointsByPlace = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]

    /// Points for finishing in `place` (1-based). Zero past the table's end,
    /// which nine cars cannot reach — it is there so the rule is total rather
    /// than a precondition every caller has to remember.
    public static func points(forPlace place: Int) -> Int {
        guard place >= 1, place <= pointsByPlace.count else { return 0 }
        return pointsByPlace[place - 1]
    }

    /// The tracks this series races, in order. Chosen at creation — drawn at
    /// random or picked by hand — and editable until the first race starts.
    public var trackIDs: [String]
    /// How many seats are competing. Fixed for the series: the field cannot
    /// change mid-tournament without making the standings meaningless.
    public var seatCount: Int
    /// One entry per completed race: the finishing order as seat indices,
    /// best first. Appended as races finish, so its count IS the progress.
    public var results: [[Int]] = []

    public init(trackIDs: [String], seatCount: Int, results: [[Int]] = []) {
        self.trackIDs = trackIDs
        self.seatCount = seatCount
        self.results = results
    }

    /// How many races the series holds.
    public var raceCount: Int { trackIDs.count }

    /// Races completed so far.
    public var completedCount: Int { results.count }

    /// Whether every race has been run.
    public var isComplete: Bool { results.count >= raceCount }

    /// The track the next race runs on, or nil when the series is over.
    public var nextTrackID: String? {
        isComplete ? nil : trackIDs[results.count]
    }

    /// The 1-based number of the race about to be run — what the chrome shows as
    /// "Race 2 of 4". Clamped at the count when the series is complete, so a
    /// results screen can still say which race just ended.
    public var currentRaceNumber: Int {
        min(results.count + 1, max(1, raceCount))
    }

    /// Points per seat, summed over every completed race.
    ///
    /// A seat missing from a result scores nothing for it rather than being an
    /// error: a car that never finished is not in the finishing order, and the
    /// series should keep going.
    public var pointsBySeat: [Int] {
        var total = Array(repeating: 0, count: seatCount)
        for order in results {
            for (place, seat) in order.enumerated() where total.indices.contains(seat) {
                total[seat] += Self.points(forPlace: place + 1)
            }
        }
        return total
    }

    /// Seats ranked best-first by points, ties broken by seat number so the
    /// order is stable. **The order is presentation only** — a tie is a shared
    /// win, and `winners` is what decides that.
    public var standings: [Int] {
        (0..<seatCount).sorted { lhs, rhs in
            let points = pointsBySeat
            let (a, b) = (points[lhs], points[rhs])
            return a != b ? a > b : lhs < rhs
        }
    }

    /// **Everyone on the top score wins.** No tie-breaker, by decision: a series
    /// that ends level ends level, and inventing a rule (countback on wins, then
    /// on seconds, then a seeded coin flip) to separate two people who scored the
    /// same would be a rule nobody asked for and nobody would remember. Four
    /// people who all took one win each all won.
    ///
    /// Empty until the series is complete — a leader mid-series is not a winner,
    /// and calling one would read as the tournament being over.
    public var winners: [Int] {
        guard isComplete, seatCount > 0 else { return [] }
        let points = pointsBySeat
        guard let best = points.max() else { return [] }
        return points.indices.filter { points[$0] == best }
    }

    /// Record a finished race. `order` is the finishing order as seat indices,
    /// best first — exactly what `Race.standings` produces.
    ///
    /// Ignored once the series is complete, so a stray results screen cannot
    /// append a fifth race to a four-race series.
    public mutating func record(order: [Int]) {
        guard !isComplete else { return }
        results.append(order)
    }
}

extension Tournament {
    /// **Draw a series' tracks from a pool.**
    ///
    /// Distinct tracks while the pool allows it, then repeats rather than a short
    /// series: a four-race tournament from a pool of three is four races on three
    /// tracks, not three races. Which matters right now — the built-in set is
    /// still small, so the pool is often near the series length.
    ///
    /// Seeded, so a draw is reproducible and a test can pin one.
    public static func draw(
        raceCount: Int, from pool: [String], seed: UInt64
    ) -> [String] {
        guard raceCount > 0, !pool.isEmpty else { return [] }
        var rng = SeededRNG(seed: seed)
        var drawn: [String] = []
        // Shuffle the whole pool and take from the front, reshuffling whenever it
        // runs dry. A per-race random pick would repeat a track twice in a row
        // even with plenty to choose from, which reads as a broken draw.
        var bag: [String] = []
        while drawn.count < raceCount {
            if bag.isEmpty {
                bag = pool.shuffled(using: &rng)
                if let last = drawn.last, bag.count > 1, bag[0] == last {
                    bag.swapAt(0, 1)
                }
                // Avoid the same track ending one shuffle and starting the next —
                // the one repeat a player would notice as "twice in a row".

            }
            drawn.append(bag.removeFirst())
        }
        return drawn
    }
}
