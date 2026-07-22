import Foundation
import SkidCore

/// Drives the deterministic sim from render-loop time: accumulates elapsed
/// wall time and steps the race at its fixed timestep, however many ticks a
/// frame owes. Rendering reads the latest state; per-player input comes
/// from the injected provider — the sim never knows which scheme or finger
/// produced it.
///
/// One session = one race. "Race again" builds a fresh session (new seed),
/// so recording/marks/timing state can never leak between runs.
///
/// Deliberately no `@Published`: the game view redraws every frame via
/// `TimelineView(.animation)` anyway, and publishing per-frame sim state
/// would mutate observable state mid-view-update.
@MainActor
public final class GameSession: ObservableObject {
    public private(set) var race: Race
    public private(set) var marks = MarkStore()
    /// The whole run as seed + inputs — replay/ghost currency, recorded
    /// from the first lap-capable build because it can't be retrofitted.
    public private(set) var recording: RaceRecording
    /// Where each gate paints its checkpoint line on the road.
    public let gateSpans: [(a: Vec2, b: Vec2)?]

    public let players: [PlayerID]
    /// The PB ghost running alongside, if any (time trial).
    public let ghost: GhostPlayback?
    private let inputFor: (PlayerID, Race) -> CarInput

    private var lastTime: TimeInterval?
    private var accumulator: TimeInterval = 0
    /// Don't spiral after a long pause (backgrounding, debugger): cap the
    /// ticks owed by any single frame.
    private static let maxTicksPerFrame = 12

    public init(
        players: [PlayerID],
        config: RaceConfig,
        seed: UInt64,
        ghost: GhostPlayback? = nil,
        inputFor: @escaping (PlayerID, Race) -> CarInput
    ) {
        let track = TrackLibrary.practiceLoop()
        self.players = players
        self.inputFor = inputFor
        self.ghost = ghost
        self.race = Race(track: track, players: players, seed: seed, config: config)
        self.recording = RaceRecording(seed: seed, players: players)
        self.gateSpans = track.gates.map { track.ribbonSpan(of: $0) }
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
            var inputs: [PlayerID: CarInput] = [:]
            for player in players {
                inputs[player] = inputFor(player, race)
            }
            recording.append(inputs)
            race.advance(inputs: inputs)
            ghost?.advanceTick()
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
}

/// mm:ss.hh from a tick count, for lap/race times.
public func formatTicks(_ ticks: Tick) -> String {
    let totalHundredths = ticks * 100 / Race.tickRate
    let minutes = totalHundredths / 6000
    let seconds = (totalHundredths % 6000) / 100
    let hundredths = totalHundredths % 100
    return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
}
