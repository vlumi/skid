import Foundation

/// A track's personal bests: the fastest full race, the fastest single lap, and one lap
/// of driving to race against.
public struct BestRecord: Equatable, Sendable, Codable {
    /// Best full-race time, in ticks past the countdown.
    public var raceTicks: Tick?
    /// The config the best race ran under (the replay needs it verbatim).
    public var raceConfig: RaceConfig?
    /// Best single lap, from any mode.
    public var bestLapTicks: Tick?

    /// **The lap you race against** — one lap, not the run it came from.
    ///
    /// This used to be the whole best race (`raceRecording`, below). A ghost is something
    /// to drive alongside, which is one lap, so storing the run was a multiple of what it
    /// shows: 3× on a three-lap race, 10× on a ten-lap one, and worse as lap count becomes
    /// a setting. A `LapGhost` is the same size whatever the race length.
    public var lapGhost: LapGhost?

    /// **The old whole-race recording, kept only to be read.**
    ///
    /// Existing books hold one, and it is a player's personal best — throwing it away on
    /// upgrade would be deleting their record to save space they had already spent. So it
    /// decodes, `migrated(on:)` turns it into a lap ghost, and nothing writes it again.
    /// Once no book in the wild has one, this field can go.
    public var raceRecording: RaceRecording?

    public init() {}

    /// Turn an old whole-race recording into a lap ghost, if this record still has one.
    ///
    /// Needs the track to replay against, which is why it is not `didSet` on decode: the
    /// book is loaded before any track is chosen, and a migration that guessed would
    /// produce a ghost for the wrong road.
    public func migrated(on track: Track) -> BestRecord {
        guard lapGhost == nil, let recording = raceRecording, let config = raceConfig else {
            return self
        }
        var record = self
        record.raceRecording = nil
        // The old recording holds no lap times, so they are recovered by replaying it —
        // the run is deterministic, so this is exact rather than an estimate.
        let replayed = recording.replay(on: track, config: config)
        let lapTimes = replayed.cars.first?.progress.lapTimes ?? []
        record.lapGhost = recording.bestLapGhost(on: track, lapTimes: lapTimes, config: config)
        return record
    }
}

/// All local hiscores, as a versioned envelope so the format can evolve
/// without eating old data (tolerant decode: unknown future version → nil,
/// caller starts fresh rather than crashing).
public struct HiscoreBook: Equatable, Sendable, Codable {
    public static let currentVersion = 1

    public var version = HiscoreBook.currentVersion
    /// Keyed by `Track.id`.
    public var tracks: [String: BestRecord] = [:]

    public init() {}

    public func best(for trackID: String) -> BestRecord {
        tracks[trackID] ?? BestRecord()
    }

    /// Record a completed lap; returns true if it's a new best.
    @discardableResult
    public mutating func recordLap(_ ticks: Tick, track trackID: String) -> Bool {
        guard !trackID.isEmpty else { return false }
        var record = best(for: trackID)
        guard ticks < (record.bestLapTicks ?? .max) else { return false }
        record.bestLapTicks = ticks
        tracks[trackID] = record
        return true
    }

    /// Record a finished race; returns true if it's a new best.
    ///
    /// **Takes the ghost already cut**, rather than the run to cut it from. The caller has
    /// the finished `Race` — its track and its lap times — while the book has only a track
    /// *id*, and recovering the lap boundaries here would mean replaying the whole run to
    /// learn something the caller already knew.
    ///
    /// A nil ghost is fine: the time is still a record, there is just nothing to race
    /// against. That is what an abandoned or lapless run leaves behind.
    @discardableResult
    public mutating func recordRace(
        ticks: Tick, ghost: LapGhost?, config: RaceConfig, track trackID: String
    ) -> Bool {
        guard !trackID.isEmpty else { return false }
        var record = best(for: trackID)
        guard ticks < (record.raceTicks ?? .max) else { return false }
        record.raceTicks = ticks
        record.lapGhost = ghost
        // The superseded whole-race recording goes with the record it belonged to.
        record.raceRecording = nil
        record.raceConfig = config
        tracks[trackID] = record
        return true
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// nil on garbage or a future version this build doesn't understand.
    public static func decode(_ data: Data) -> HiscoreBook? {
        guard let book = try? JSONDecoder().decode(HiscoreBook.self, from: data),
            book.version <= currentVersion
        else { return nil }
        return book
    }
}
