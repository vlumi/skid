import Foundation

/// **A key the keyboard scheme listens to** — platform-neutral, so the routing
/// is testable without an event system. The Mac shell maps its key codes onto
/// these; nothing else in the game knows a keyboard exists.
public enum KeyboardKey: Hashable, CaseIterable, Sendable {
    case w, a, s, d
    case up, down, left, right

    /// The two clusters a shared keyboard splits into: left hand, right hand.
    public enum Cluster: Sendable {
        case wasd, arrows
    }

    /// What a key does, whichever cluster it belongs to.
    public enum Drive: Sendable {
        case gas, brake, left, right
    }

    public var cluster: Cluster {
        switch self {
        case .w, .a, .s, .d: return .wasd
        case .up, .down, .left, .right: return .arrows
        }
    }

    public var drive: Drive {
        switch self {
        case .w, .up: return .gas
        case .s, .down: return .brake
        case .a, .left: return .left
        case .d, .right: return .right
        }
    }
}

/// **Pro-style digital driving from held keys**: gas/brake on one axis,
/// left/right on the other.
///
/// Full deflection on press, with no ramp of its own: the SIM already
/// rate-limits steering (`CarTuning.steerRate`, ~0.1 s to full lock), so a tap
/// slews into the turn rather than snapping to lock — the same smoothing every
/// scheme gets, which keeps a keyboard car mechanically identical to a touch one.
///
/// Opposite keys cancel: left+right is straight, gas+brake is coasting. And
/// KEYS are held, not directions — a lone driver pressing W and ↑ together who
/// lets go of W is still on the gas.
public final class KeyboardControlSource: ControlSource {
    public private(set) var held: Set<KeyboardKey> = []

    public init() {}

    public func press(_ key: KeyboardKey) { held.insert(key) }
    public func release(_ key: KeyboardKey) { held.remove(key) }
    public func releaseAll() { held.removeAll() }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        func on(_ drive: KeyboardKey.Drive) -> Double {
            held.contains { $0.drive == drive } ? 1 : 0
        }
        return CarInput(steer: on(.right) - on(.left), throttle: on(.gas) - on(.brake))
    }
}

/// **One keyboard, up to two drivers.** A lone driver gets BOTH clusters —
/// whichever hand they prefer — and two split them: WASD is the left-hand seat
/// (P1), the arrows the right (P2).
///
/// A release clears the key from whichever seat holds it rather than
/// re-routing it, so a key pressed before the seat count changed can never be
/// stuck down.
public final class KeyboardSeats {
    /// Two clusters, two drivers. A third person has no keys.
    public static let maxSeats = 2

    public let seats: [KeyboardControlSource] = (0..<maxSeats).map { _ in KeyboardControlSource() }
    /// How many people are driving from this keyboard right now.
    public var humans = 1

    public init() {}

    /// The seat `key` drives, or nil when nobody is at the keyboard.
    public func seat(for key: KeyboardKey) -> Int? {
        guard humans >= 1 else { return nil }
        if humans == 1 { return 0 }
        return key.cluster == .wasd ? 0 : 1
    }

    public func press(_ key: KeyboardKey) {
        guard let seat = seat(for: key) else { return }
        seats[seat].press(key)
    }

    public func release(_ key: KeyboardKey) {
        for seat in seats { seat.release(key) }
    }

    /// Lets go of everything — when the window loses focus a key-up never
    /// arrives, and a car would otherwise drive on by itself.
    public func releaseAll() {
        for seat in seats { seat.releaseAll() }
    }

    public func source(forSeat seat: Int) -> KeyboardControlSource? {
        seats.indices.contains(seat) ? seats[seat] : nil
    }
}
