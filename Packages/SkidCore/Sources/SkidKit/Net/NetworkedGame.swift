import Foundation
import SkidCore
import SwiftUI

/// **The lobby and the networked race, as one observable thing the UI can watch.**
///
/// Owns the transport, the roster, and the `NetworkedRace` coordinator; drives the
/// send/receive loop each frame. Everything that decides *whether the sim may step*
/// lives in `SkidCore` and is already tested — this is the part that needs a radio
/// and a screen, and it is kept as thin as that allows.
@MainActor
public final class NetworkedGame:
    ObservableObject, RaceTransportDelegate, GameSession.LockstepDriver
{
    /// Where in the flow we are. The UI switches on this and nothing else.
    public enum Phase: Equatable {
        case idle
        /// Advertising, waiting for guests. Only the host sees this.
        case hosting
        /// Browsing for a host.
        case joining
        /// Connected, roster agreed, waiting for the host to start.
        case lobby
        /// Racing.
        case racing
        /// Over, or abandoned. `reason` is nil for a clean finish.
        case ended(reason: String?)
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var peers: [RaceRoster.PeerName] = []
    @Published public private(set) var roster = RaceRoster()
    /// What to show when the race is not moving, or nil when it is. Read per
    /// frame by the overlay; NOT published, for the reason on `bufferedTicks`.
    public private(set) var stallNote: String?
    /// Set once if the peers ever disagree. Sticky, and worth surfacing loudly:
    /// it is the one outcome that means the whole design does not work.
    ///
    /// Not published either — it is set from the tick loop. The overlay reads it
    /// every frame anyway, since `RaceScreen` redraws continuously.
    public private(set) var divergenceNote: String?
    /// Buffered input ticks — the health readout. Growing means falling behind.
    ///
    /// **Not `@Published`, and that is load-bearing.** This is updated on every
    /// simulated tick, and `RaceScreen` observes this object — so publishing it
    /// mutated observable state from inside the render pass, which invalidated the
    /// view, which re-entered the tick loop. The lobby reached `.racing` and the
    /// app then froze solid. `GameSession` already documents the same trap and
    /// deliberately publishes nothing per-frame; this reintroduced it.
    public private(set) var bufferedTicks = 0
    /// Why a device could not be seated, for the host's lobby. A join that fails
    /// silently is indistinguishable from one that never arrived.
    @Published public private(set) var joinNote: String?
    /// **A running log of the handshake, shown in the lobby.** Two device sessions
    /// were spent on failures whose cause was invisible from the screen — a peer
    /// name collision, then a lobby that stopped responding. On-device is the only
    /// place this flow can be observed, so it reports itself.
    @Published public private(set) var trace: [String] = []

    private func note(_ line: String) {
        trace.append(line)
        if trace.count > 12 { trace.removeFirst(trace.count - 12) }
    }

    /// How many players this device brings.
    public var localSeats: Int = 1

    private let transport: MultipeerTransport
    private var net: NetworkedRace?
    private var start: RaceStart?
    /// Set by the host so a guest can be told what to race on.
    private var pendingStart: ((RaceStart) -> Void)?

    public var me: RaceRoster.PeerName { transport.me }
    public var isHost: Bool { roster.host == transport.me }

    public init(displayName: String) {
        transport = MultipeerTransport(displayName: displayName)
        transport.delegate = self
    }

    // MARK: - Lobby

    /// Host a race: seat ourselves first, so the host is always seat 0.
    public func host(seats: Int) {
        localSeats = seats
        roster = RaceRoster()
        try? roster.join(transport.me, seats: seats)
        phase = .hosting
        note("hosting as \(DeviceName.display(transport.me))")
        transport.startHosting()
    }

    public func join(seats: Int) {
        localSeats = seats
        roster = RaceRoster()
        phase = .joining
        note("looking for a host as \(DeviceName.display(transport.me))")
        transport.startBrowsing()
    }

    public func leave() {
        transport.disconnect()
        net = nil
        start = nil
        roster = RaceRoster()
        peers = []
        phase = .idle
    }

    /// Host only: freeze the roster, tell everyone what to race, and begin.
    ///
    /// **The host's own start goes through the same path as a guest's.** Building
    /// the race locally from its own state and only *sending* the start would let
    /// the two diverge the moment the two code paths disagree about anything — so
    /// the host applies its own message, exactly as a guest does.
    public func startRace(
        course: RaceStart.Course, seed: UInt64, laps: Int?, delayTicks: Int = 2
    ) {
        // Traced BEFORE the guard: "the note that did not print" has been the only
        // usable signal from a device each time this flow broke.
        note("start tapped: isHost=\(isHost)")
        guard isHost else {
            note("REFUSED: not the host (me=\(DeviceName.display(transport.me)))")
            return
        }
        let message = RaceStart(
            course: course, seed: seed, roster: roster, laps: laps, delayTicks: delayTicks)
        note("sending start: seed \(seed), \(roster.seatCount) cars")
        transport.send(message.encoded, reliable: true)
        // **Discovery is NOT torn down here.** Stopping the advertiser mid-handshake
        // can drop the MC session, which arrives as `peerLeft` — and that removed
        // the guest from the roster, disabling the Start button the host had just
        // pressed and stranding the lobby with no way forward. Latecomers are
        // already impossible once `phase` leaves `.hosting` (see `seat`), so
        // stopping the radio is an optimisation, not a correctness measure.
        apply(message)
    }

    private func apply(_ message: RaceStart) {
        let mine = message.roster.seats(for: transport.me).map(\.rawValue)
        note("starting \(message.roster.seatCount) cars, my seats \(mine)")
        start = message
        roster = message.roster
        net = NetworkedRace(
            roster: message.roster, me: transport.me, delayTicks: message.delayTicks)
        stallNote = nil
        divergenceNote = nil
        phase = .racing
        pendingStart?(message)
    }

    /// Called by whatever builds the actual `GameSession`, so this type never has
    /// to know about tracks or rendering.
    public func onStart(_ handler: @escaping (RaceStart) -> Void) {
        pendingStart = handler
        if let start { handler(start) }
    }

    // MARK: - Driving the race

    /// Seats this device reads thumbs for.
    public var mySeats: [PlayerID] { net?.localSeats ?? [] }

    /// Publish this device's input for `tick` and take in whatever has arrived.
    /// Call once per frame, before asking for ticks.
    public func publish(_ inputs: [PlayerID: CarInput], at tick: Tick) {
        guard var net else { return }
        let bytes = net.send(inputs, at: tick)
        self.net = net
        transport.send(bytes, reliable: false)
    }

    /// The next tick's inputs, or nil if the race must wait. **Nil means do not
    /// step the sim** — not "everybody coasts".
    public func nextTick() -> [PlayerID: CarInput]? {
        guard var net else { return nil }
        let inputs = net.nextTick()
        self.net = net
        refreshDiagnostics()
        return inputs
    }

    /// Report the state we reached, so peers can compare. Call after every tick.
    public func report(hash: UInt64, at tick: Tick) {
        guard var net else { return }
        let bytes = net.report(hash: hash, at: tick)
        self.net = net
        transport.send(bytes, reliable: false)
        refreshDiagnostics()
    }

    private func refreshDiagnostics() {
        guard let net else { return }
        bufferedTicks = net.clock.bufferedTicks
        stallNote = Self.describe(net.stall, roster: net.roster)
        if let divergence = net.divergence, divergenceNote == nil {
            divergenceNote =
                "Desync at tick \(divergence.tick) vs \(DeviceName.display(divergence.peer))"
        }
    }

    private static func describe(_ error: Error, peer: RaceRoster.PeerName) -> String {
        let name = DeviceName.display(peer)
        switch error as? RaceRoster.JoinError {
        case .fieldFull(_, let available):
            return available == 0
                ? "\(name) could not join: the field is full"
                : "\(name) could not join: room for only \(available) more"
        case .alreadyJoined:
            return "\(name) is already in the race"
        case .seatCountOutOfRange(let requested, let max):
            return "\(name) asked for \(requested) seats; \(max) is the most per device"
        case nil:
            return "\(name) could not join"
        }
    }

    /// A stall needs a cause on screen. A frozen race with no explanation is
    /// indistinguishable from a crash, and this is the whole point of `Stall`
    /// naming what it is waiting for.
    private static func describe(_ stall: LockstepClock.Stall?, roster: RaceRoster) -> String? {
        switch stall {
        case .waitingForInput(_, let missing):
            let names = Set(
                missing.compactMap { roster.peer(driving: $0) }.map(DeviceName.display)
            ).sorted()
            return names.isEmpty ? "Waiting…" : "Waiting for \(names.joined(separator: ", "))"
        case .buffering, nil:
            // Buffering is the normal state between ticks, not something to report.
            return nil
        }
    }

    // MARK: - RaceTransportDelegate

    public func transport(didReceive bytes: [UInt8], from peer: RaceRoster.PeerName) {
        // Lobby messages first: they are rarer and distinguishable by tag.
        if let request = JoinRequest(bytes: bytes) {
            seat(peer, seats: request.seats)
            return
        }
        if let update = RosterUpdate(bytes: bytes) {
            guard !isHost else { return }  // the host is the source of truth
            roster = update.roster
            phase = .lobby
            return
        }
        if let message = RaceStart(bytes: bytes) {
            guard !isHost else { return }  // our own start, echoed back
            apply(message)
            return
        }
        guard var net else { return }
        net.receive(bytes, from: peer)
        self.net = net
        refreshDiagnostics()
    }

    public func transport(peerJoined peer: RaceRoster.PeerName) {
        peers = transport.connectedPeers
        note("connected: \(DeviceName.display(peer))")
        if isHost {
            // The host waits to be told how many seats the guest brings.
            return
        }
        // Guest: announce ourselves.
        transport.send(JoinRequest(seats: localSeats).encoded, reliable: true)
        phase = .lobby
    }

    public func transport(peerLeft peer: RaceRoster.PeerName) {
        peers = transport.connectedPeers
        note("lost: \(DeviceName.display(peer))")
        if case .racing = phase {
            // **The race stalls rather than ending.** Its cars still have to be
            // simulated by everyone else, and quietly dropping them would fork the
            // race. Whether to abandon it is the player's call.
            net?.peerLeft(peer)
            refreshDiagnostics()
            stallNote = "Lost \(DeviceName.display(peer))"
            return
        }
        // Once the start message has gone out the roster is FROZEN: the race is
        // built from it on every device, so editing it here would leave the peers
        // disagreeing about who is in the field. A departure after that point is a
        // stall, handled above.
        guard start == nil else { return }
        roster.remove(peer: peer)
        if isHost { transport.send(RosterUpdate(roster: roster).encoded, reliable: true) }
    }

    private func seat(_ peer: RaceRoster.PeerName, seats: Int) {
        guard isHost, case .hosting = phase else { return }
        // **A refused join must be visible.** `try?` here swallowed the reason a
        // device failed to appear, and that cost a device session: two phones both
        // called "iPhone" collided as one peer, the join was rejected as
        // `alreadyJoined`, and the lobby simply showed one device with Start
        // disabled and no explanation. Unique peer keys fix the collision; this
        // makes any future refusal say so.
        do {
            try roster.join(peer, seats: seats)
            joinNote = nil
            note("seated \(DeviceName.display(peer)) (\(seats)) -> \(roster.seatCount) cars")
        } catch {
            joinNote = Self.describe(error, peer: peer)
            return  // nothing changed, so there is no new roster to push
        }
        // Guests cannot derive the roster themselves: only the host assigns seat
        // numbers, so without this push a guest's lobby stays empty until the race
        // starts, which reads as a broken join.
        transport.send(RosterUpdate(roster: roster).encoded, reliable: true)
    }
}
