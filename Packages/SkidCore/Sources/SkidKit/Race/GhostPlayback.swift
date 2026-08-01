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
