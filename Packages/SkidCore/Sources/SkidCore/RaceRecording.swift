import Foundation

/// A complete run as data: the seed plus the per-tick input stream. Because
/// the sim is deterministic, replaying this through the same track/config/
/// tuning reproduces the race bit-for-bit — this is the future replay,
/// ghost, and lockstep currency, captured from the first lap-capable build
/// because it can't be retrofitted.
public struct RaceRecording: Equatable, Sendable, Codable {
    public var seed: UInt64
    public var players: [PlayerID]
    /// One entry per tick, in order.
    public var inputs: [[PlayerID: CarInput]]

    public init(seed: UInt64, players: [PlayerID]) {
        self.seed = seed
        self.players = players
        self.inputs = []
    }

    /// **Records what the sim will step, not what the thumb sent.**
    ///
    /// `Race.advance` quantises its inputs, so a recording of the raw values holds numbers
    /// the race never used — it would replay a near-miss of the run, and a packed ghost
    /// (four bytes a tick) could not round-trip it at all. Quantising here means a caller
    /// cannot get this wrong by handing over what it happened to have.
    public mutating func append(_ tickInputs: [PlayerID: CarInput]) {
        inputs.append(tickInputs.mapValues(\.quantised))
    }

    /// Re-run the whole recording and return the resulting race state.
    public func replay(
        on track: Track, tuning: CarTuning = CarTuning(), config: RaceConfig = RaceConfig()
    ) -> Race {
        var race = Race(track: track, players: players, tuning: tuning, seed: seed, config: config)
        step(&race) { _ in }
        return race
    }

    /// Re-run the recording, collecting `Race.stateHash` after every tick.
    ///
    /// The sequence a lockstep divergence check compares — one number per tick,
    /// so two runs are not merely unequal but disagree *at a tick*. Networking
    /// will compare a live peer's sequence against this; a test compares two local
    /// ones. Same operation either way, which is why it lives here rather than in
    /// the tests that use it first.
    public func replayHashes(
        on track: Track, tuning: CarTuning = CarTuning(), config: RaceConfig = RaceConfig()
    ) -> [UInt64] {
        var race = Race(track: track, players: players, tuning: tuning, seed: seed, config: config)
        var hashes: [UInt64] = []
        hashes.reserveCapacity(inputs.count)
        step(&race) { hashes.append($0.stateHash) }
        return hashes
    }

    private func step(_ race: inout Race, after: (Race) -> Void) {
        for tickInputs in inputs {
            race.advance(inputs: tickInputs)
            after(race)
        }
    }
}

// MARK: - Keeping only the lap worth racing

extension RaceRecording {
    /// **Which ticks of a run cover its fastest lap.**
    ///
    /// `lapTimes` holds each lap's duration in order and laps run back to back from the
    /// end of the countdown, so this is arithmetic rather than a search. Nil when the run
    /// completed no laps — there is then no lap to keep.
    public static func bestLapRange(lapTimes: [Tick], countdownTicks: Tick) -> Range<Tick>? {
        guard let best = lapTimes.min(), let index = lapTimes.firstIndex(of: best) else {
            return nil
        }
        let start = countdownTicks + lapTimes[..<index].reduce(0, +)
        return start..<(start + best)
    }
}
