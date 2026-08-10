import Foundation
import SkidCore
import SwiftUI

/// **The lobby and the networked race, as one observable thing the UI can watch.**
///
/// Owns the transport, the roster, and the host-authoritative sync (`HostRelay`
/// on the host, `ClientView` on a guest). Everything that decides what a frame
/// shows lives in `SkidCore` and is tested under latency and loss — this is the
/// part that needs a radio and a screen, and it is kept as thin as that allows.
@MainActor
public final class NetworkedGame: ObservableObject, RaceTransportDelegate, NetworkedRaceDriver {
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
    /// frame by the overlay and deliberately NOT `@Published`: it changes per
    /// frame, `RaceScreen` observes this object, and publishing per-frame state
    /// from inside the render pass froze the app solid once already.
    public private(set) var stallNote: String?
    /// The client's link, measured: worst recent arrival gap and the latency the
    /// jitter buffer is paying to absorb it. Plain (not `@Published`) and updated
    /// about once a second — the instrument the next device session reads, so a
    /// bad link is a number rather than an adjective.
    public private(set) var linkNote: String?
    private var linkNoteAge: TimeInterval = 0
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
    /// The host's half of the sync, or nil on a client.
    private var relay: HostRelay?
    /// The client's half, or nil on the host.
    private var clientView: ClientView?
    private var start: RaceStart?
    /// Set by the host so a guest can be told what to race on.
    private var pendingStart: ((RaceStart) -> Void)?
    /// Set by `adoptForTesting` so per-tick traffic lands in `outbox` rather than
    /// going to a transport there is none of.
    private var captureSends = false

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
        relay = nil
        clientView = nil
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
        course: RaceStart.Course, seed: UInt64, laps: Int?,
        tuning: CarTuning = CarTuning(), carContact: Bool = true
    ) {
        // Traced BEFORE the guard: "the note that did not print" has been the only
        // usable signal from a device each time this flow broke.
        note("start tapped: isHost=\(isHost)")
        guard isHost else {
            note("REFUSED: not the host (me=\(DeviceName.display(transport.me)))")
            return
        }
        let message = RaceStart(
            course: course, seed: seed, roster: roster, laps: laps,
            tuning: tuning, carContact: carContact)
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
        if message.roster.host == transport.me {
            relay = HostRelay(roster: message.roster, me: transport.me)
        } else {
            clientView = ClientView(roster: message.roster, me: transport.me)
        }
        stallNote = nil
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
    public var mySeats: [PlayerID] { start?.roster.seats(for: transport.me) ?? [] }

    public var isRaceHost: Bool { relay != nil }

    /// Host: the freshest thumb a remote seat has sent — held between packets,
    /// which is safe here and nowhere else, because the host's sim IS the race.
    public func remoteInput(for seat: PlayerID) -> CarInput {
        relay?.input(for: seat) ?? .coast
    }

    /// Host: called after every simulated tick; sends a snapshot on the cadence
    /// ticks. Unreliable on purpose — a lost snapshot is superseded by the next
    /// one 50 ms later, and the reliable channel's coalescing turned a 60 Hz
    /// stream into 2 Hz clumps once already.
    public func broadcast(_ race: Race) {
        guard let relay, relay.shouldBroadcast(after: race.tick) else { return }
        let bytes = HostRelay.snapshotMessage(for: race)
        if captureSends { outbox.append(bytes) } else { transport.send(bytes, reliable: false) }
    }

    /// Client: this frame's thumbs, off to the host. `ClientView` decides which
    /// frames actually send — the spike's measured lesson is that MC congests
    /// above ~100 small messages a second.
    public func publish(_ inputs: [PlayerID: CarInput]) {
        guard var view = clientView else { return }
        let bytes = view.publish(inputs)
        clientView = view
        guard let bytes else { return }
        if captureSends { outbox.append(bytes) } else { transport.send(bytes, reliable: false) }
    }

    /// Client: the smoothed state to draw. Also where the one remaining stall
    /// note comes from — a host gone quiet is the only thing left that can
    /// freeze a client, and it should say so rather than look like a crash.
    public func view(advancedBy dt: TimeInterval) -> RaceSnapshot? {
        guard var view = clientView else { return nil }
        let shown = view.view(advancedBy: dt)
        clientView = view
        linkNoteAge += dt
        if linkNoteAge > 1 {
            linkNoteAge = 0
            let lagMs = Int(view.lagTicks * 1000 / Double(Race.tickRate))
            linkNote = "gap \(view.worstGapMs) ms · lag \(lagMs) ms"
        }
        if stallNote == nil, view.isStarved {
            stallNote = "Waiting for \(DeviceName.display(roster.host ?? "the host"))"
        } else if stallNote != nil, !view.isStarved {
            stallNote = nil
        }
        return shown
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

    // MARK: - RaceTransportDelegate

    public func transport(didReceive bytes: [UInt8], from peer: RaceRoster.PeerName) {
        // Lobby messages first: they are rarer and distinguishable by tag. Ignored
        // once the race has started — the roster is frozen, and a late-arriving
        // reliable lobby message must not rewrite the field mid-race.
        if let request = JoinRequest(bytes: bytes) {
            if start == nil { seat(peer, seats: request.seats) }
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
        // Per-tick traffic: inputs to the host's relay, snapshots to the client's
        // view. Anything unrecognised — including the retired lockstep hash tag —
        // is dropped, never believed.
        if var relay {
            relay.receive(bytes, from: peer)
            self.relay = relay
        } else if var view = clientView {
            view.receive(bytes, from: peer)
            clientView = view
        }
    }

    public func transport(peerJoined peer: RaceRoster.PeerName) {
        peers = transport.connectedPeers
        note("connected: \(DeviceName.display(peer))")
        // **A peer state change during a race must not restart the lobby.** MC
        // reports connections at times of its own choosing, and re-announcing here
        // would reset the guest's phase out of `.racing` and re-send a JoinRequest
        // that the host would try to seat mid-race.
        guard start == nil else { return }
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
            // The race carries on — that is the model's point. On the host a
            // departed player's cars coast; on a client, only the HOST leaving
            // matters, and it should read as a disconnection, not a hang.
            if var relay {
                relay.peerLeft(peer)
                self.relay = relay
                stallNote = "Lost \(DeviceName.display(peer))"
            } else if peer == roster.host {
                stallNote = "Lost \(DeviceName.display(peer)) — the race is over"
            }
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

    // MARK: - Test seams

    /// Bytes this device would have sent, captured instead of transmitted — so two
    /// `NetworkedGame`s can be driven against each other in one process. The device
    /// failures that cost the most were all in this loop, and nothing could exercise
    /// it without a radio.
    private var outbox: [[UInt8]] = []

    /// Start a race without a lobby handshake.
    func adoptForTesting(_ message: RaceStart) {
        captureSends = true
        apply(message)
    }

    /// Take everything queued since the last call.
    func drainOutbox() -> [[UInt8]] {
        defer { outbox.removeAll() }
        return outbox
    }

    /// Feed in what a peer sent.
    func deliverForTesting(_ bytes: [UInt8], from peer: RaceRoster.PeerName) {
        transport(didReceive: bytes, from: peer)
    }
}
