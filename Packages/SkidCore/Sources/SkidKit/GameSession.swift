import Foundation
import SkidCore

/// Drives the deterministic sim from render-loop time: accumulates elapsed
/// wall time and steps the race at its fixed timestep, however many ticks a
/// frame owes. Rendering reads the latest state; input comes from whatever
/// `ControlSource` was injected — the sim never knows which.
///
/// Deliberately no `@Published`: the game view redraws every frame via
/// `TimelineView(.animation)` anyway, and publishing per-frame sim state
/// would mutate observable state mid-view-update.
@MainActor
public final class GameSession: ObservableObject {
    /// A three-lap race with a three-second countdown.
    static let raceConfig = RaceConfig(laps: 3, countdownTicks: 3 * Race.tickRate)

    public private(set) var race: Race
    public private(set) var marks = MarkStore()
    /// The whole run as seed + inputs — replay/ghost currency, recorded
    /// from the first lap-capable build because it can't be retrofitted.
    public private(set) var recording: RaceRecording

    public let player = PlayerID(0)
    /// Swappable in-run — the A/B seam.
    public var controlSource: ControlSource

    private var lastTime: TimeInterval?
    private var accumulator: TimeInterval = 0
    private var seed: UInt64 = 1
    /// Don't spiral after a long pause (backgrounding, debugger): cap the
    /// ticks owed by any single frame.
    private static let maxTicksPerFrame = 12

    public init(controlSource: ControlSource) {
        self.controlSource = controlSource
        self.race = Race(
            track: TrackLibrary.practiceLoop(),
            players: [PlayerID(0)],
            seed: 1,
            config: Self.raceConfig
        )
        self.recording = RaceRecording(seed: 1, players: [PlayerID(0)])
    }

    /// Advance sim time to `time` (a `TimelineView` timestamp, seconds).
    public func advance(to time: TimeInterval) {
        guard let last = lastTime else {
            lastTime = time
            return
        }
        lastTime = time
        accumulator += max(0, time - last)

        var ticks = 0
        while accumulator >= Race.dt, ticks < Self.maxTicksPerFrame {
            let input = controlSource.input(for: player, at: race.tick)
            let inputs = [player: input]
            recording.append(inputs)
            race.advance(inputs: inputs)
            for car in race.cars {
                marks.record(car: car, on: race.track, tick: race.tick)
            }
            accumulator -= Race.dt
            ticks += 1
        }
        if ticks == Self.maxTicksPerFrame {
            accumulator = 0
        }
    }

    public func reset() {
        seed += 1
        race = Race(
            track: race.track, players: [player], seed: seed, config: Self.raceConfig
        )
        recording = RaceRecording(seed: seed, players: [player])
        marks.reset()
        accumulator = 0
        lastTime = nil
    }
}

/// mm:ss.hh from a tick count, for lap/race times.
public func formatTicks(_ ticks: Tick) -> String {
    let totalHundredths = ticks * 100 / Race.tickRate
    let minutes = totalHundredths / 6000
    let seconds = (totalHundredths % 6000) / 100
    let hundredths = totalHundredths % 100
    return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
}
