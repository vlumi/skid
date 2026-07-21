/// Identifies one player for the whole run of a race, across every mode —
/// local thumb, AI, keyboard, or (later) a network peer.
public struct PlayerID: Hashable, Sendable, Codable, Comparable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (a: PlayerID, b: PlayerID) -> Bool { a.rawValue < b.rawValue }
}

/// Simulation tick counter at the fixed timestep.
public typealias Tick = Int

/// Car-RELATIVE input for one tick: steer + throttle, nothing
/// screen-oriented. Every control scheme, AI, and network peer reduces to
/// this — the sim never knows which produced it.
public struct CarInput: Equatable, Sendable, Codable {
    /// -1 (full left) … 1 (full right).
    public var steer: Double
    /// -1 (brake/reverse) … 1 (full gas). 0 coasts.
    public var throttle: Double

    public init(steer: Double = 0, throttle: Double = 0) {
        self.steer = max(-1, min(1, steer))
        self.throttle = max(-1, min(1, throttle))
    }

    public static let coast = CarInput()
}

/// A control scheme is an input source, not a game mode. Touch zones,
/// on-screen sticks, AI, keyboard, GameController, and network peers are all
/// just ControlSources producing CarInput per player per tick.
public protocol ControlSource {
    func input(for player: PlayerID, at tick: Tick) -> CarInput
}
