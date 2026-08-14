import Foundation
import SkidCore

/// **The personal-best LAP**, replayed tick-by-tick through its own parallel sim —
/// determinism makes the stored pose + inputs reproduce it exactly. Never interacts with
/// the live race and never writes marks; it only gets drawn (translucently).
///
/// One lap rather than the whole best race, which is what was stored before: a ghost is
/// something to drive alongside, and the laps either side of the best one were never
/// visible. See `LapGhost`.
@MainActor
public final class GhostPlayback {
    private(set) var race: Race
    private let inputs: [[PlayerID: CarInput]]
    private var index = 0

    public init?(record: BestRecord, track: Track) {
        guard let ghost = record.lapGhost, let config = record.raceConfig else { return nil }
        self.race = Race(
            track: track, players: ghost.players, seed: ghost.seed, config: config)
        // **Seeded to the lap's start**, since these inputs were driven from there rather
        // than from the grid.
        self.race.seed(from: ghost.start)
        self.inputs = ghost.inputs
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
