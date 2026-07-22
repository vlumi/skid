import Foundation

/// A track's personal bests: the fastest full race (with the run that set
/// it, as seed + inputs — the ghost) and the fastest single lap.
public struct BestRecord: Equatable, Sendable, Codable {
    /// Best full-race time, in ticks past the countdown.
    public var raceTicks: Tick?
    /// The recording of the best race — replayable as the PB ghost.
    public var raceRecording: RaceRecording?
    /// The config the best race ran under (the replay needs it verbatim).
    public var raceConfig: RaceConfig?
    /// Best single lap, from any mode.
    public var bestLapTicks: Tick?

    public init() {}
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

    /// Record a finished race; returns true if it's a new best (and stores
    /// the run's recording as the new ghost).
    @discardableResult
    public mutating func recordRace(
        ticks: Tick, recording: RaceRecording, config: RaceConfig, track trackID: String
    ) -> Bool {
        guard !trackID.isEmpty else { return false }
        var record = best(for: trackID)
        guard ticks < (record.raceTicks ?? .max) else { return false }
        record.raceTicks = ticks
        record.raceRecording = recording
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
