import Foundation

// Split out of `Race.swift` on the file-length limit: the car, its progress
// and the event stream are what the OUTSIDE of the sim consumes, while the
// stepping stays where it happens.

/// One car's progress through the gate sequence. A lap is earned by
/// crossing every gate in order, in the driving direction — cutting the
/// track can never skip ahead.
public struct CarProgress: Equatable, Sendable, Codable {
    /// Index into `track.gates` of the next gate that counts.
    public var nextGate = 0
    /// Completed laps.
    public var lap = 0
    /// Tick the current lap started at.
    public var lapStartTick: Tick = 0
    /// Completed lap durations, in ticks.
    public var lapTimes: [Tick] = []
    /// Tick the car took the flag, once it has.
    public var finishedAt: Tick?

    public init() {}

    public var bestLapTicks: Tick? { lapTimes.min() }
}

/// One car in the race: identity + dynamic state + race progress.
public struct Car: Equatable, Sendable, Codable {
    public let id: PlayerID
    public var state: CarState
    public var progress = CarProgress()

    public init(id: PlayerID, state: CarState) {
        self.id = id
        self.state = state
    }
}

/// Something audible/tactile that happened during a tick — derived
/// deterministically from the sim, consumed by sound/haptics. Never fed
/// back into physics.
public enum RaceEvent: Equatable, Sendable {
    case wallImpact(PlayerID, speed: Double)
    case carImpact(PlayerID, PlayerID, closingSpeed: Double)
    /// An INTERMEDIATE gate — crossing the finish line emits `lapCompleted`
    /// (or `finished`) instead, so one crossing is one event.
    case gateCrossed(PlayerID)
    case lapCompleted(PlayerID, lapTicks: Tick)
    case finished(PlayerID)
}
