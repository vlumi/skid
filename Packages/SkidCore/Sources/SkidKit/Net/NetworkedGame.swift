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
        /// Browsing for a host — nothing chosen yet.
        case joining
        /// Asked to join a specific host; waiting for its verdict.
        case awaitingApproval
        /// Connected, roster agreed, waiting for the host to start.
        case lobby
        /// Racing.
        case racing
        /// Over, or abandoned. `reason` is nil for a clean finish.
        case ended(reason: String?)
    }

    @Published public internal(set) var phase: Phase = .idle
    @Published public internal(set) var peers: [RaceRoster.PeerName] = []
    @Published public internal(set) var roster = RaceRoster()
    /// What to show when the race is not moving, or nil when it is. Read per
    /// frame by the overlay and deliberately NOT `@Published`: it changes per
    /// frame, `RaceScreen` observes this object, and publishing per-frame state
    /// from inside the render pass froze the app solid once already.
    public internal(set) var stallNote: String?
    /// The client's link, measured: worst recent arrival gap and the latency the
    /// jitter buffer is paying to absorb it. Plain (not `@Published`) and updated
    /// about once a second — the instrument the next device session reads, so a
    /// bad link is a number rather than an adjective.
    public internal(set) var linkNote: String?
    var linkNoteAge: TimeInterval = 0
    /// Why a device could not be seated, for the host's lobby. A join that fails
    /// silently is indistinguishable from one that never arrived.
    @Published public private(set) var joinNote: String?
    /// **A running log of the handshake, shown in the lobby.** Two device sessions
    /// were spent on failures whose cause was invisible from the screen — a peer
    /// name collision, then a lobby that stopped responding. On-device is the only
    /// place this flow can be observed, so it reports itself.
    @Published public private(set) var trace: [String] = []

    func note(_ line: String) {
        trace.append(line)
        if trace.count > 12 { trace.removeFirst(trace.count - 12) }
    }

    /// How many players this device brings.
    public var localSeats: Int = 1
    /// The host this guest chose, so a second advertiser's traffic is ignored.
    var chosenHost: RaceRoster.PeerName?

    /// Hosts this device can see and choose between. Only a browsing guest fills
    /// this — the spike joined whatever it found first, which is fine for a spike
    /// and wrong in a room with two races in it.
    @Published public internal(set) var visibleHosts: [RaceRoster.PeerName] = []
    /// Guests waiting on the host's yes or no, in arrival order.
    @Published public internal(set) var pendingJoins: [PendingJoin] = []
    /// Why the race ended, when it ended for a reason worth naming.
    @Published public internal(set) var endedReason: String?

    /// A guest asking in, and how many seats it brings.
    public struct PendingJoin: Equatable, Identifiable {
        public let peer: RaceRoster.PeerName
        public let seats: Int
        public var id: RaceRoster.PeerName { peer }
        /// What the host's lobby shows on the button.
        public var display: String { DeviceName.display(peer) }
    }

    let transport: MultipeerTransport
    /// Losses waiting out their grace period — a brief drop is not a departure.
    var presence = PeerPresence()
    /// What the last race was raced on, so Rematch needs no new decisions.
    var lastCourse: RaceStart.Course?
    var lastTuning = CarTuning()
    var lastCarContact = true
    /// The host's half of the sync, or nil on a client.
    var relay: HostRelay?
    /// The client's half, or nil on the host.
    var clientView: ClientView?
    var start: RaceStart?
    /// Set by the host so a guest can be told what to race on.
    private var pendingStart: ((RaceStart) -> Void)?
    /// Set by `adoptForTesting` so per-tick traffic lands in `outbox` rather than
    /// going to a transport there is none of.
    var captureSends = false

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
        resetSession()
        try? roster.join(transport.me, seats: seats)
        phase = .hosting
        note("hosting as \(DeviceName.display(transport.me))")
        transport.startHosting()
    }

    public func join(seats: Int) {
        localSeats = seats
        roster = RaceRoster()
        resetSession()
        phase = .joining
        note("looking for a host as \(DeviceName.display(transport.me))")
        transport.startBrowsing()
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
        transmit(message.encoded, reliable: true)
        // **Discovery is NOT torn down here.** Stopping the advertiser mid-handshake
        // can drop the MC session, which arrives as `peerLeft` — and that removed
        // the guest from the roster, disabling the Start button the host had just
        // pressed and stranding the lobby with no way forward. Latecomers are
        // already impossible once `phase` leaves `.hosting` (see `seat`), so
        // stopping the radio is an optimisation, not a correctness measure.
        apply(message)
    }

    func apply(_ message: RaceStart) {
        let mine = message.roster.seats(for: transport.me).map(\.rawValue)
        note("starting \(message.roster.seatCount) cars, my seats \(mine)")
        start = message
        roster = message.roster
        // Remembered so Rematch needs no new decisions from anybody.
        lastCourse = message.course
        lastTuning = message.tuning
        lastCarContact = message.carContact
        endedReason = nil
        presence.reset()
        generation += 1
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

    /// Bumped for every race, so a session built for an earlier one can tell it is
    /// obsolete. A rematch leaves the old session alive for a frame or two, and
    /// both hold this same driver.
    public private(set) var generation = 0

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
        // The host's grace clock ticks with the sim, which is the only clock it has.
        noteTime(Race.dt)
        guard let relay, relay.shouldBroadcast(after: race.tick) else { return }
        let bytes = HostRelay.snapshotMessage(for: race)
        transmit(bytes, reliable: false)
    }

    /// Client: this frame's thumbs, off to the host. `ClientView` decides which
    /// frames actually send — the spike's measured lesson is that MC congests
    /// above ~100 small messages a second.
    public func publish(_ inputs: [PlayerID: CarInput]) {
        guard var view = clientView else { return }
        let bytes = view.publish(inputs)
        clientView = view
        guard let bytes else { return }
        transmit(bytes, reliable: false)
    }

    /// Client: the smoothed state to draw. Also where the one remaining stall
    /// note comes from — a host gone quiet is the only thing left that can
    /// freeze a client, and it should say so rather than look like a crash.
    public func view(advancedBy dt: TimeInterval) -> RaceSnapshot? {
        noteTime(dt)
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
        // Lobby traffic first — rarer, reliable, and distinguishable by tag. Race
        // traffic is the hot path and falls through.
        if receiveLobbyMessage(bytes, from: peer) { return }
        // Per-tick traffic: inputs to the host's relay, snapshots to the client's
        // view. Anything unrecognized — including the retired lockstep hash tag —
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
        // **A returning peer inside its grace period is not a new arrival**, and
        // this must run BEFORE the racing guard below: the grace period exists for
        // mid-race hiccups, so a race is exactly when a recovery needs noticing.
        // Checking it after the guard meant a returning player was never recovered
        // during a race and got ejected anyway when the grace expired.
        if presence.recovered(peer) {
            note("recovered: \(DeviceName.display(peer))")
            // Clear the fading notice, or a player who came back is still announced
            // as dropping out for the rest of the race.
            stallNote = nil
            return
        }
        // **A peer state change during a race must not restart the lobby.** MC
        // reports connections at times of its own choosing, and re-announcing here
        // would reset the guest's phase out of `.racing` and re-send a JoinRequest
        // that the host would try to seat mid-race.
        guard start == nil else { return }
        if isHost {
            // The host waits to be asked, and then decides. See `approve`.
            return
        }
        // Guest: a visible host to choose from. Announcing ourselves is now a
        // deliberate act (`askToJoin`), not a reflex — a room can hold two races.
        if !visibleHosts.contains(peer) { visibleHosts.append(peer) }
        // Already chosen this host (a reconnect during the handshake): re-ask.
        if peer == chosenHost { askToJoin(peer) }
    }

    public func transport(peerLeft peer: RaceRoster.PeerName) {
        peers = transport.connectedPeers
        note("link down: \(DeviceName.display(peer))")
        visibleHosts.removeAll { $0 == peer }
        pendingJoins.removeAll { $0.peer == peer }
        // **Provisional.** MC reports a peer lost on brief interruptions, so this
        // is a fading link, not a departure, until the grace period says otherwise
        // (see `PeerPresence` and `noteTime`). Ejecting someone for a hiccup is the
        // failure mode that matters here.
        guard start != nil else {
            // Not racing: nobody is mid-corner, so the lobby can just drop them.
            peerDeparted(peer, byHost: peer == roster.host, announced: false)
            return
        }
        presence.lost(peer)
        stallNote = "\(DeviceName.display(peer)) is dropping out…"
    }

    /// A peer is gone for good — announced, or its grace expired.
    ///
    /// The asymmetry is the whole of it: a guest leaving costs its own cars, while
    /// the host leaving ends the race, because there is no race without the device
    /// simulating it.
    func peerDeparted(
        _ peer: RaceRoster.PeerName, byHost: Bool, announced: Bool
    ) {
        note("\(announced ? "left" : "dropped"): \(DeviceName.display(peer))")
        if byHost || peer == roster.host, !isHost {
            let why = announced ? "The host left the race" : "Lost the host"
            transport.disconnect()
            resetSession()
            roster = RaceRoster()
            peers = []
            endedReason = why
            phase = .ended(reason: why)
            return
        }
        // A guest is out: its cars leave the field, and the host tells everyone by
        // pushing the shortened roster. Mid-race the roster stays FROZEN — every
        // device built its race from it — so the cars simply coast (`HostRelay`
        // already does that) and the field changes at the next race.
        if var relay {
            relay.peerLeft(peer)
            self.relay = relay
        }
        stallNote =
            announced
            ? "\(DeviceName.display(peer)) left"
            : "\(DeviceName.display(peer)) dropped out"
        guard start == nil else { return }
        roster.remove(peer: peer)
        if isHost { transmit(RosterUpdate(roster: roster).encoded, reliable: true) }
    }

    /// Advance the grace clock. Called once a frame by whoever is driving the race
    /// — timing lives in `PeerPresence`, not in a scattering of timers here.
    public func noteTime(_ dt: TimeInterval) {
        for peer in presence.advance(by: dt) {
            peerDeparted(peer, byHost: peer == roster.host, announced: false)
        }
    }

    func seat(_ peer: RaceRoster.PeerName, seats: Int) {
        // **Out of a race, whatever the lobby phase is.** This used to demand
        // `.hosting`, which was true when seating happened automatically on
        // connect — but the host also sits in `.lobby` between races now, and
        // `approve` is an explicit act that must not be silently dropped. `start`
        // is the real condition: the roster freezes when a race begins.
        //
        // `receiveLobbyMessage` already drops a mid-race request, so this is the
        // second of two guards on the field's integrity — deliberately, because
        // seating someone into a frozen roster would leave every device disagreeing
        // about who is racing, and that class of bug cost a device session.
        guard isHost, start == nil else { return }
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
        transmit(RosterUpdate(roster: roster).encoded, reliable: true)
    }

    /// Bytes this device would have sent, captured instead of transmitted — so two
    /// `NetworkedGame`s can be driven against each other in one process. The device
    /// failures that cost the most were all in this loop, and nothing could exercise
    /// it without a radio.
    /// A stored property cannot live in an extension, so this stays with the
    /// class while the seams that use it live in `NetworkedTestSeams.swift`.
    var outbox: [[UInt8]] = []

    /// **The only way bytes leave this device.** Every send goes through here so the
    /// test seam cannot diverge from production: `decline` sent via `transport`
    /// directly and its message vanished in tests, which read as a protocol bug and
    /// was a plumbing one.
    func transmit(_ bytes: [UInt8], reliable: Bool) {
        if captureSends {
            outbox.append(bytes)
        } else {
            transport.send(bytes, reliable: reliable)
        }
    }
}
