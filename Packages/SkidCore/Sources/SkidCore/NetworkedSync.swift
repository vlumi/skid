import Foundation

/// **The host-authoritative wire, both ends of it.**
///
/// One device — the host — simulates the one true race. Everyone else sends
/// thumbs and renders snapshots. Nothing here can stall and nothing can
/// diverge: a late input means one car coasts a moment on the host's sim, a
/// late snapshot means the client interpolates a moment longer.
///
/// Transport-free like everything before it: bytes in, bytes out, testable
/// with latency and loss in one process. Message tags share the space the
/// lockstep spike used — input stays tag 1 in the same positional format,
/// snapshots take tag 3, and the retired hash tag 2 is ignored on receipt.
public enum SyncMessage {
    static let inputTag: UInt8 = 1
    static let snapshotTag: UInt8 = 3
}

/// The host's half: hold the latest input per remote seat, broadcast the state.
///
/// **"Hold the last input" was the forbidden move under lockstep** — a peer
/// inventing input forked the race. Under a host authority it is the natural
/// move: the host's sim is the race, so there is nothing to fork. A quiet seat
/// keeps doing what it last said until a fresher packet lands.
public struct HostRelay: Sendable {
    public let roster: RaceRoster
    public let me: RaceRoster.PeerName

    /// Simulation ticks between snapshots: 3 → 20 a second. The rate lesson from
    /// the spike, applied: MC congests somewhere above ~100 small messages a
    /// second per device, so the host sends 20 and each client sends 30, with
    /// headroom for a full lobby.
    public static let snapshotEvery: Tick = 3

    private var latestTick: [PlayerID: Tick] = [:]
    private var latestInput: [PlayerID: CarInput] = [:]

    public init(roster: RaceRoster, me: RaceRoster.PeerName) {
        self.roster = roster
        self.me = me
    }

    /// The input the host's sim should apply for a remote seat, right now.
    public func input(for seat: PlayerID) -> CarInput {
        latestInput[seat] ?? .coast
    }

    /// Take a client's packet. Only input from a seated peer counts; anything
    /// older than what a seat already has is superseded, not applied — the
    /// unreliable channel reorders, and driving a car by a stale packet would
    /// yank it backwards mid-corner.
    @discardableResult
    public mutating func receive(_ bytes: [UInt8], from peer: RaceRoster.PeerName) -> Bool {
        guard peer != me, bytes.first == SyncMessage.inputTag else { return false }
        let seats = roster.seats(for: peer)
        guard !seats.isEmpty,
            let packet = LockstepClock.Packet(bytes: Array(bytes.dropFirst()), roster: seats),
            let newest = packet.inputs.first
        else { return false }
        for seat in seats {
            guard packet.tick > latestTick[seat] ?? -1, let input = newest[seat] else { continue }
            latestTick[seat] = packet.tick
            latestInput[seat] = input.input
        }
        return true
    }

    /// A departed peer's cars coast rather than repeating their last order
    /// forever — a held full-throttle from someone who walked away would grind
    /// along a wall for the rest of the race.
    public mutating func peerLeft(_ peer: RaceRoster.PeerName) {
        for seat in roster.seats(for: peer) {
            latestInput[seat] = .coast
        }
    }

    /// Whether this tick is a broadcast tick.
    public func shouldBroadcast(after tick: Tick) -> Bool {
        tick % Self.snapshotEvery == 0
    }

    /// The snapshot message for the race as it stands.
    public static func snapshotMessage(for race: Race) -> [UInt8] {
        [SyncMessage.snapshotTag] + RaceSnapshot(of: race).encoded
    }
}

/// The client's half: send thumbs, buffer snapshots, render a smoothed view a
/// short, fixed distance behind the newest one.
public struct ClientView: Sendable {
    public let roster: RaceRoster
    public let me: RaceRoster.PeerName
    public let localSeats: [PlayerID]

    /// The floor for how far behind the newest snapshot the view renders, in
    /// ticks. One and a half snapshot intervals: enough that the next snapshot
    /// usually lands before the view needs it on a healthy link.
    static let minLag = 4.5
    /// The ceiling: three quarters of a second. A link whose bursts exceed this
    /// is a link to report, not to smooth over.
    static let maxLag = 45.0
    /// Send thumbs every Nth frame. 30 a second is plenty for a held analog
    /// value the host holds between packets, and half the message rate.
    static let inputEveryNthFrame = 2

    private var snapshots: [RaceSnapshot] = []
    private var renderTick: Double = -1
    private var frame = 0
    private var inputTick: Tick = 0
    private var sinceLastSnapshot: TimeInterval = 0
    /// Peak-held arrival gap, decaying slowly — the jitter the lag must cover.
    private var worstGap: TimeInterval = 0

    public init(roster: RaceRoster, me: RaceRoster.PeerName) {
        self.roster = roster
        self.me = me
        self.localSeats = roster.seats(for: me)
    }

    /// This frame's thumbs, as a packet — or nil on the frames that skip.
    public mutating func publish(_ inputs: [PlayerID: CarInput]) -> [UInt8]? {
        inputTick += 1
        frame += 1
        guard frame % Self.inputEveryNthFrame == 0 else { return nil }
        var frame: [PlayerID: CarInputWire] = [:]
        for seat in localSeats {
            frame[seat] = CarInputWire(inputs[seat] ?? .coast)
        }
        let packet = LockstepClock.Packet(tick: inputTick, inputs: [frame])
        return [SyncMessage.inputTag] + packet.encoded(roster: localSeats)
    }

    /// Take a host message. Snapshots from anyone but the host are refused —
    /// only one device's word is the race.
    @discardableResult
    public mutating func receive(_ bytes: [UInt8], from peer: RaceRoster.PeerName) -> Bool {
        guard peer == roster.host, bytes.first == SyncMessage.snapshotTag,
            let snapshot = RaceSnapshot(bytes: Array(bytes.dropFirst()))
        else { return false }
        // The unreliable channel reorders; an older snapshot is superseded, not
        // rendered — the view must never move backwards.
        guard snapshot.tick > (snapshots.last?.tick ?? -1) else { return false }
        snapshots.append(snapshot)
        if snapshots.count > 32 { snapshots.removeFirst(snapshots.count - 32) }
        // Peak-hold the arrival gap with a slow decay: the lag rises to a burst
        // immediately (one pause) and relaxes over ~10 s once the link calms.
        worstGap = max(sinceLastSnapshot, worstGap * 0.995)
        sinceLastSnapshot = 0
        return true
    }

    /// The state to draw, `dt` seconds after the last call. Nil until the first
    /// snapshot arrives.
    public mutating func view(advancedBy dt: TimeInterval) -> RaceSnapshot? {
        sinceLastSnapshot += dt
        guard let newest = snapshots.last else { return nil }
        let target = Double(newest.tick) - lagTicks
        if renderTick < 0 || renderTick < Double(newest.tick) - 2 * lagTicks - 6 {
            renderTick = target  // first frame, or hopelessly behind: snap
        } else {
            // **Play out at a steady 1×, with only a small rate skew toward the
            // target.** The first version leaned proportionally (10% of the
            // error per frame), which turned a bursty arrival STAIR into rate
            // modulation — sprint after each burst, crawl before the next — and
            // the crawl rendered as the very pulse the buffer exists to remove.
            // A jitter buffer's job is a constant playout rate; the skew only
            // trims drift, slowly enough to be invisible.
            let skew = min(0.08, max(-0.08, (target - renderTick) * 0.01))
            renderTick += dt * Double(Race.tickRate) * (1 + skew)
            renderTick = min(renderTick, Double(newest.tick))
        }
        return interpolatedSnapshot(at: renderTick)
    }

    /// **How far behind the newest snapshot to render, adapted to the link.**
    ///
    /// A fixed small lag assumes snapshots arrive steadily, and on device they
    /// did not: the transport delivered in ~500 ms bursts (the peer-to-peer
    /// radio duty-cycles), so a 75 ms buffer starved between bursts and the
    /// client pulsed at the burst rate — the 2 Hz stutter that survived the
    /// model change, because it was never the model. The lag now covers the
    /// worst recent arrival gap plus one snapshot interval, so a bursty link
    /// costs latency instead of rhythm. Smooth-but-later is the snapshot
    /// model's trade to make; lockstep never had the option.
    public var lagTicks: Double {
        min(Self.maxLag, max(Self.minLag, worstGap * Double(Race.tickRate) + 3))
    }

    /// The worst recent arrival gap, for the on-screen link readout — the next
    /// device session should measure the link, not describe it.
    public var worstGapMs: Int { Int(worstGap * 1000) }

    /// True when the host has gone quiet long enough that the view is a freeze
    /// frame — what the "waiting" chrome keys off.
    public var isStarved: Bool { sinceLastSnapshot > 1.0 }

    /// The newest tick the host has told us about, for diagnostics.
    public var newestTick: Tick { snapshots.last?.tick ?? -1 }

    private func interpolatedSnapshot(at tick: Double) -> RaceSnapshot? {
        guard let newest = snapshots.last else { return nil }
        guard tick < Double(newest.tick) else { return newest }
        // Find the pair bracketing the render tick; older gaps are fine, the
        // interpolation just spans them.
        var older = snapshots.first
        var newer = newest
        for snapshot in snapshots {
            if Double(snapshot.tick) <= tick {
                older = snapshot
            } else {
                newer = snapshot
                break
            }
        }
        guard let from = older, from.tick < newer.tick else { return newer }
        let alpha = (tick - Double(from.tick)) / Double(newer.tick - from.tick)
        return RaceSnapshot.interpolated(from: from, to: newer, alpha: alpha)
    }
}
