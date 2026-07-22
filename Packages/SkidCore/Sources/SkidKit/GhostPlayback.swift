import Foundation
import SkidCore

/// The personal-best run, replayed tick-by-tick through its own parallel
/// sim — determinism makes the stored seed + inputs reproduce it exactly.
/// Never interacts with the live race and never writes marks; it only gets
/// drawn (translucently).
@MainActor
public final class GhostPlayback {
    private(set) var race: Race
    private let inputs: [[PlayerID: CarInput]]
    private var index = 0

    public init?(record: BestRecord, track: Track) {
        guard let recording = record.raceRecording, let config = record.raceConfig else {
            return nil
        }
        self.race = Race(
            track: track, players: recording.players, seed: recording.seed, config: config)
        self.inputs = recording.inputs
    }

    public var isDone: Bool { index >= inputs.count }

    /// The ghost's cars, while the replay is still running.
    public var cars: [CarState] {
        isDone ? [] : race.cars.map(\.state)
    }

    public func advanceTick() {
        guard index < inputs.count else { return }
        race.advance(inputs: inputs[index])
        index += 1
    }
}

/// Loads/saves the hiscore book as JSON in Application Support. All the
/// interesting logic (versioning, improve-only records) lives in
/// `HiscoreBook` in the core, where it's tested.
@MainActor
public final class HiscoreFile {
    private let url: URL

    public init() {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Skid", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("hiscores.json")
    }

    public func load() -> HiscoreBook {
        guard let data = try? Data(contentsOf: url), let book = HiscoreBook.decode(data) else {
            return HiscoreBook()
        }
        return book
    }

    public func save(_ book: HiscoreBook) {
        guard let data = try? book.encoded() else { return }
        try? data.write(to: url, options: .atomic)
    }
}
