import Foundation

/// A track's personal bests: the fastest full race, the fastest single lap, and one lap
/// of driving to race against.
///
/// Bumping `HiscoreBook.currentVersion` is how this format changes: a book written by an
/// older build decodes to nil and the player starts fresh. That is cheap here in a way it
/// would not be for tracks or profiles — a record belongs to a specific road, and the roads
/// are still changing.
public struct BestRecord: Equatable, Sendable, Codable {
    /// Best full-race time, in ticks past the countdown.
    public var raceTicks: Tick?
    /// The config the best race ran under (the replay needs it verbatim).
    public var raceConfig: RaceConfig?
    /// Best single lap, from any mode.
    public var bestLapTicks: Tick?

    /// **Who set the best lap**, and who set the best race. Nil for a guest, which is
    /// honest rather than a hole: a guest chose not to give a name, and inventing
    /// "Player 1" would attribute a time to somebody who does not exist.
    ///
    /// **The NAME, not the profile id.** A record is a snapshot of something that
    /// happened: deleting the profile afterwards does not un-drive the lap, and renaming
    /// yourself does not make last week's record somebody else's. An id would leave a
    /// dangling reference on delete and silently rewrite history on rename — both wrong
    /// for a board whose whole job is to say what happened.
    public var lapHolder: String?
    public var raceHolder: String?

    /// **The lap you race against** — one lap, not the run it came from.
    ///
    /// This used to be the whole best race (`raceRecording`, below). A ghost is something
    /// to drive alongside, which is one lap, so storing the run was a multiple of what it
    /// shows: 3× on a three-lap race, 10× on a ten-lap one, and worse as lap count becomes
    /// a setting. A `LapGhost` is the same size whatever the race length.
    public var lapGhost: LapGhost?

    public init() {}
}

/// All local hiscores, as a versioned envelope so the format can evolve
/// without eating old data (tolerant decode: unknown future version → nil,
/// caller starts fresh rather than crashing).
public struct HiscoreBook: Equatable, Sendable, Codable {
    /// **2: ghosts became one packed lap.**
    ///
    /// A version-1 book holds whole-race recordings, which this build has no reader for —
    /// and deliberately so. Migrating them was written and then deleted: a ghost is only
    /// meaningful on the road it was driven on, the built-in tracks are still changing as
    /// the library grows, and a lap replayed through a track that has moved is a car
    /// driving through grass. Old books therefore decode to nil and the player starts
    /// fresh, which `decode` already does for any version it does not understand.
    /// 3: the compiler gained a run-off margin (`PieceCompiler.runOff`), which
    /// translates every compiled track — and a ghost's start pose is in world
    /// coordinates, so every stored ghost would start one margin off and drive
    /// into the grass. Times would still be true; the ghosts would not.
    public static let currentVersion = 3

    public var version = HiscoreBook.currentVersion
    /// Keyed by `Track.id`.
    public var tracks: [String: BestRecord] = [:]

    public init() {}

    public func best(for trackID: String) -> BestRecord {
        tracks[trackID] ?? BestRecord()
    }

    /// Record a completed lap; returns true if it's a new best.
    ///
    /// `holder` is the driver's name, or nil for a guest. It is stored ONLY when the time
    /// is taken, so a slower lap by somebody else cannot rewrite whose record it is.
    @discardableResult
    public mutating func recordLap(
        _ ticks: Tick, track trackID: String, holder: String? = nil
    ) -> Bool {
        guard !trackID.isEmpty else { return false }
        var record = best(for: trackID)
        guard ticks < (record.bestLapTicks ?? .max) else { return false }
        record.bestLapTicks = ticks
        record.lapHolder = holder
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
        ticks: Tick, ghost: LapGhost?, config: RaceConfig, track trackID: String,
        holder: String? = nil
    ) -> Bool {
        guard !trackID.isEmpty else { return false }
        var record = best(for: trackID)
        guard ticks < (record.raceTicks ?? .max) else { return false }
        record.raceTicks = ticks
        record.lapGhost = ghost
        record.raceConfig = config
        record.raceHolder = holder
        tracks[trackID] = record
        return true
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// nil on garbage, or on any version that is not this one.
    ///
    /// **Older books are refused as well as newer ones**, which is stricter than the usual
    /// tolerant-decode shape and is deliberate here: version 1 stored whole-race
    /// recordings, and a lenient decode would have accepted such a book and quietly dropped
    /// the ghost as an unknown key — leaving a record that claims a time with nothing to
    /// race against. Refusing means the player starts fresh, which is the intended outcome
    /// (see `currentVersion`) rather than a silent half-migration.
    ///
    /// A future format may well be worth reading forward from. That is a decision for
    /// whoever writes version 3, with the data in front of them.
    public static func decode(_ data: Data) -> HiscoreBook? {
        guard let book = try? JSONDecoder().decode(HiscoreBook.self, from: data),
            book.version == currentVersion
        else { return nil }
        return book
    }
}
