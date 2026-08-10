import Foundation

/// **What the race needs from a network, and nothing more.**
///
/// The seam that keeps MultipeerConnectivity out of the simulation. `HostRelay`
/// and `ClientView` produce and consume `[UInt8]`; this is how those bytes get
/// moved, and it is
/// deliberately small enough that the UDP escape hatch (Network.framework) is a
/// second conformance rather than a rewrite.
///
/// **Two delivery modes, because the race needs both.** Per-tick input is
/// `unreliable`: it is repaired by redundancy (`LockstepClock.Packet.history`), so
/// a retransmitted 40 ms late packet is worse than useless — it arrives after the
/// tick it belonged to and only adds head-of-line delay. Lobby traffic is
/// `reliable`: a lost roster or seed does not repeat, and ordering matters more
/// than latency.
public protocol RaceTransport: AnyObject {
    /// This device's name, and the key the sync layer uses for "mine".
    var me: RaceRoster.PeerName { get }
    /// Peers currently connected.
    var connectedPeers: [RaceRoster.PeerName] { get }

    /// Send to everyone. `reliable` traffic is guaranteed and ordered; unreliable
    /// traffic may be dropped or reordered, which per-tick input tolerates by design.
    func send(_ bytes: [UInt8], reliable: Bool)

    /// Called on the main actor when bytes arrive, when a peer connects, and when
    /// one goes away.
    var delegate: RaceTransportDelegate? { get set }
}

/// The transport's side of the conversation.
@MainActor
public protocol RaceTransportDelegate: AnyObject {
    func transport(didReceive bytes: [UInt8], from peer: RaceRoster.PeerName)
    func transport(peerJoined peer: RaceRoster.PeerName)
    func transport(peerLeft peer: RaceRoster.PeerName)
}

// MARK: - The lobby handshake

/// **What every peer must agree before a single tick runs.**
///
/// Not sent per tick — sent once, reliably, by the host. Everything here is an
/// input to the simulation that is *not* a thumb: get one of them wrong and the
/// two devices are deterministically simulating different races, which the
/// divergence watch would then report as a mysterious tick-1 disagreement.
///
/// The track travels as its **share code**, not as a compiled `Track`: the code is
/// the project's existing portable spelling of a track, it already round-trips, and
/// it means a guest can race a track it has never seen. A built-in travels as its
/// slug.
public struct RaceStart: Equatable, Sendable, Codable {
    /// Which track — a builtin slug, or a share code for a custom one.
    public enum Course: Equatable, Sendable, Codable {
        case builtin(String)
        case shared(String)
    }

    public var course: Course
    /// The grid shuffle's seed. Same seed, same starting positions.
    public var seed: UInt64
    /// Everybody's seats. The host assigns these; guests do not renumber.
    public var roster: RaceRoster
    /// Laps, countdown — the rules both peers score against.
    public var laps: Int?
    /// Whether cars collide. Physics, so the host owns it — the same trap as
    /// `tuning`: it was read from each device's own settings, and two peers
    /// disagreeing about whether a touch is a collision diverge on first contact.
    public var carContact: Bool
    /// **The physics, from the host.**
    ///
    /// Nineteen numbers that decide how a car accelerates, grips and slides. Each
    /// device used to race with its OWN persisted tuning — so any value a player had
    /// nudged on either phone made the cars physically different, and the two sims
    /// diverged from the first applied input. Measured on device: a repeatable desync
    /// at tick 182, which is `countdownTicks + delayTicks` — the very first tick whose
    /// input is not locked to coast.
    ///
    /// The tuning panel stays a local toy for local play. In a networked race there
    /// is one set of physics and the host owns it, for the same reason it owns the
    /// seed: anything the simulation reads must come from one place.
    public var tuning: CarTuning

    public init(
        course: Course, seed: UInt64, roster: RaceRoster, laps: Int?,
        tuning: CarTuning = CarTuning(), carContact: Bool = true
    ) {
        self.course = course
        self.seed = seed
        self.roster = roster
        self.laps = laps
        self.tuning = tuning
        self.carContact = carContact
    }

    /// Reliable-channel bytes. JSON rather than the compact packing used for
    /// per-tick input: this is sent **once**, so clarity beats 400 bytes, and a
    /// lobby message that is easy to inspect is easier to debug on two devices.
    public var encoded: [UInt8] {
        guard let data = try? JSONEncoder().encode(self) else { return [] }
        return [RaceStart.tag] + [UInt8](data)
    }

    public init?(bytes: [UInt8]) {
        guard bytes.first == RaceStart.tag,
            let decoded = try? JSONDecoder().decode(
                RaceStart.self, from: Data(bytes.dropFirst()))
        else { return nil }
        self = decoded
    }

    /// Distinct from `SyncMessage`'s per-tick tags, so one receive path can tell a
    /// lobby message from race traffic.
    static let tag: UInt8 = 200
}

/// A guest's answer to "how many of you are there?", sent on joining.
public struct JoinRequest: Equatable, Sendable, Codable {
    public var seats: Int

    public init(seats: Int) {
        self.seats = seats
    }

    public var encoded: [UInt8] {
        guard let data = try? JSONEncoder().encode(self) else { return [] }
        return [JoinRequest.tag] + [UInt8](data)
    }

    public init?(bytes: [UInt8]) {
        guard bytes.first == JoinRequest.tag,
            let decoded = try? JSONDecoder().decode(
                JoinRequest.self, from: Data(bytes.dropFirst()))
        else { return nil }
        self = decoded
    }

    static let tag: UInt8 = 201
}

/// The host's current roster, pushed to guests whenever it changes.
///
/// Without this a guest sees an empty lobby until the race starts: only the host
/// knows who has been seated, because only the host assigns seat numbers. Sent
/// reliably — a lost roster does not repeat itself, and a guest showing the wrong
/// field is the kind of confusion that reads as a bug.
public struct RosterUpdate: Equatable, Sendable, Codable {
    public var roster: RaceRoster

    public init(roster: RaceRoster) {
        self.roster = roster
    }

    public var encoded: [UInt8] {
        guard let data = try? JSONEncoder().encode(self) else { return [] }
        return [RosterUpdate.tag] + [UInt8](data)
    }

    public init?(bytes: [UInt8]) {
        guard bytes.first == RosterUpdate.tag,
            let decoded = try? JSONDecoder().decode(
                RosterUpdate.self, from: Data(bytes.dropFirst()))
        else { return nil }
        self = decoded
    }

    static let tag: UInt8 = 202
}

/// **Announcing a departure, rather than being noticed missing.**
///
/// A peer that taps Leave says so on the reliable channel, and the difference
/// matters: a silent exit only becomes visible when the grace period expires
/// (`PeerPresence`), so for three seconds a car nobody is driving keeps its last
/// input. An announced one is immediate and unambiguous — the host drops the
/// seats now, and everyone knows it was a choice rather than a bad link.
///
/// `byHost` is the asymmetry: a guest leaving removes its own cars, while the
/// host leaving ends the race for everyone, because there is no race without the
/// device simulating it.
public struct LeaveNotice: Equatable, Sendable, Codable {
    public var byHost: Bool

    public init(byHost: Bool) {
        self.byHost = byHost
    }

    public var encoded: [UInt8] {
        guard let data = try? JSONEncoder().encode(self) else { return [] }
        return [LeaveNotice.tag] + [UInt8](data)
    }

    public init?(bytes: [UInt8]) {
        guard bytes.first == LeaveNotice.tag,
            let decoded = try? JSONDecoder().decode(
                LeaveNotice.self, from: Data(bytes.dropFirst()))
        else { return nil }
        self = decoded
    }

    static let tag: UInt8 = 203
}

/// The host's answer to a `JoinRequest`.
///
/// **Not a security feature** — the roster's field cap already bounds who gets
/// in, and anyone in radio range can be seen. It exists so the host knows who
/// arrived and can say no, and so a refusal reaches the guest as a sentence
/// instead of a lobby that never fills. A declined guest hears why; a silent
/// refusal was the failure that already cost a device session.
public struct JoinVerdict: Equatable, Sendable, Codable {
    public var accepted: Bool
    /// Shown to the declined guest. Empty when accepted.
    public var reason: String

    public init(accepted: Bool, reason: String = "") {
        self.accepted = accepted
        self.reason = reason
    }

    public var encoded: [UInt8] {
        guard let data = try? JSONEncoder().encode(self) else { return [] }
        return [JoinVerdict.tag] + [UInt8](data)
    }

    public init?(bytes: [UInt8]) {
        guard bytes.first == JoinVerdict.tag,
            let decoded = try? JSONDecoder().decode(
                JoinVerdict.self, from: Data(bytes.dropFirst()))
        else { return nil }
        self = decoded
    }

    static let tag: UInt8 = 204
}
