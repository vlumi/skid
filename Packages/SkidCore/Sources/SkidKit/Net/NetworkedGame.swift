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
public final class NetworkedGame: ObservableObject, RaceTransportDelegate {
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
    /// What to show when the race is not moving, or nil when it is.
    @Published public private(set) var stallNote: String?
    /// Set once if the peers ever disagree. Sticky, and worth surfacing loudly:
    /// it is the one outcome that means the whole design does not work.
    @Published public private(set) var divergenceNote: String?
    /// Buffered input ticks — the health readout. Growing means falling behind.
    @Published public private(set) var bufferedTicks = 0

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
        transport.startHosting()
    }

    public func join(seats: Int) {
        localSeats = seats
        roster = RaceRoster()
        phase = .joining
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
        guard isHost else { return }
        transport.stopDiscovery()  // no latecomers once the lights are on
        let message = RaceStart(
            course: course, seed: seed, roster: roster, laps: laps, delayTicks: delayTicks)
        transport.send(message.encoded, reliable: true)
        apply(message)
    }

    private func apply(_ message: RaceStart) {
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
                "Desync at tick \(divergence.tick) vs \(divergence.peer)"
        }
    }

    /// A stall needs a cause on screen. A frozen race with no explanation is
    /// indistinguishable from a crash, and this is the whole point of `Stall`
    /// naming what it is waiting for.
    private static func describe(_ stall: LockstepClock.Stall?, roster: RaceRoster) -> String? {
        switch stall {
        case .waitingForInput(_, let missing):
            let names = Set(missing.compactMap { roster.peer(driving: $0) }).sorted()
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
        if case .racing = phase {
            // **The race stalls rather than ending.** Its cars still have to be
            // simulated by everyone else, and quietly dropping them would fork the
            // race. Whether to abandon it is the player's call.
            net?.peerLeft(peer)
            refreshDiagnostics()
            stallNote = "Lost \(peer)"
            return
        }
        roster.remove(peer: peer)
        if isHost { transport.send(RosterUpdate(roster: roster).encoded, reliable: true) }
    }

    private func seat(_ peer: RaceRoster.PeerName, seats: Int) {
        guard isHost, case .hosting = phase else { return }
        // A refused join is not fatal — the guest simply never appears in the
        // roster, and the host's lobby shows the field is full.
        try? roster.join(peer, seats: seats)
        // Guests cannot derive the roster themselves: only the host assigns seat
        // numbers, so without this push a guest's lobby stays empty until the race
        // starts, which reads as a broken join.
        transport.send(RosterUpdate(roster: roster).encoded, reliable: true)
    }
}
