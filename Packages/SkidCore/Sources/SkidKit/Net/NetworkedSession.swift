import Foundation
import SkidCore

/// **The session loop: leaving, racing again, and joining on purpose.**
///
/// Split from `NetworkedGame` because it is a different concern with the same
/// owner — that class drives a race, this drives the *session around* races — and
/// because a couch plays five short races in a row. Force-quitting both apps
/// between them was what made networked play untestable at any real length.
///
/// The UI over this is deliberately minimal: the menus get a complete redesign
/// later (a proper new-game flow, with real thought about what is selectable
/// where) and it will replace whatever chrome exists now. So this buys mechanics,
/// not layout.
@MainActor
extension NetworkedGame {
    /// **Leave for good** — announce it, then tear the session down.
    ///
    /// Announced rather than silent: a peer that vanishes is only noticed when its
    /// grace period expires, so for three seconds its car keeps its last input.
    /// Saying so makes it immediate, and tells everyone it was a choice rather
    /// than a bad link. The notice goes first, because `disconnect` closes the
    /// channel it would travel on.
    public func leave() {
        if start != nil || phase == .lobby || phase == .hosting {
            transmit(LeaveNotice(byHost: isHost).encoded, reliable: true)
        }
        transport.disconnect()
        resetSession()
        roster = RaceRoster()
        peers = []
        phase = .idle
    }

    /// **Leave the race, keep the connection** — back to the lobby, ready to race
    /// again. This is the common case a session actually needs: a couch plays five
    /// short races, not one, and force-quitting between them is what made the
    /// feature untestable.
    public func returnToLobby(reason: String? = nil) {
        endedReason = reason
        relay = nil
        clientView = nil
        start = nil
        stallNote = nil
        linkNote = nil
        presence.reset()
        // **Advertising was never stopped**, so there is nothing to resume: the
        // spike tore the advertiser down when a race began and that dropped the MC
        // session mid-handshake, so it stays up for the whole session. Restarting it
        // here would be the same mistake on a slower fuse. Latecomers are refused by
        // `seat` while a race is running, which is the real gate.
        phase = isHost ? .hosting : .lobby
    }

    /// Everything that belongs to one session rather than to the app.
    func resetSession() {
        relay = nil
        clientView = nil
        start = nil
        stallNote = nil
        linkNote = nil
        endedReason = nil
        presence.reset()
        pendingJoins = []
        visibleHosts = []
        lastCourse = nil
    }

    // MARK: - Joining on purpose

    /// Guest: ask a specific host to let us in. The spike joined whatever it saw
    /// first, which in a room with two races is a coin toss.
    public func askToJoin(_ host: RaceRoster.PeerName) {
        guard phase == .joining || phase == .awaitingApproval else { return }
        chosenHost = host
        phase = .awaitingApproval
        note("asking \(DeviceName.display(host)) to join")
        transmit(JoinRequest(seats: localSeats, colors: localColors).encoded, reliable: true)
    }

    /// Host: yes. The roster is the gate that can still refuse (a full field), and
    /// its reason travels back rather than vanishing.
    public func approve(_ peer: RaceRoster.PeerName) {
        guard isHost, let pending = pendingJoins.first(where: { $0.peer == peer }) else { return }
        pendingJoins.removeAll { $0.peer == peer }
        seat(pending.peer, seats: pending.seats, colors: pending.colors)
    }

    /// Host: no. Deliberately not a security feature — the field cap already bounds
    /// who gets in — but the host should know who arrived and be able to say no,
    /// and the guest should hear it as a sentence rather than a silence.
    public func decline(_ peer: RaceRoster.PeerName) {
        guard isHost else { return }
        pendingJoins.removeAll { $0.peer == peer }
        note("declined \(DeviceName.display(peer))")
        transmit(JoinVerdict(accepted: false, reason: "The host declined").encoded, reliable: true)
    }

    /// The lobby half of the receive path — join requests and verdicts, the roster,
    /// the start message, and a leaving peer. Returns whether it recognized the
    /// bytes, so the caller can fall through to race traffic.
    func receiveLobbyMessage(_ bytes: [UInt8], from peer: RaceRoster.PeerName) -> Bool {
        if let request = JoinRequest(bytes: bytes) {
            // The host decides now, rather than seating whoever asks. Ignored once
            // a race is running: the roster is frozen, and a late reliable message
            // must not rewrite the field mid-race.
            guard isHost, start == nil, !pendingJoins.contains(where: { $0.peer == peer })
            else { return true }
            pendingJoins.append(
                PendingJoin(peer: peer, seats: request.seats, colors: request.colors))
            note("join request from \(DeviceName.display(peer)) (\(request.seats))")
            return true
        }
        if let verdict = JoinVerdict(bytes: bytes) {
            guard !isHost, peer == chosenHost, !verdict.accepted else { return true }
            // Declined: back to browsing, with the reason on screen. A refusal that
            // showed nothing was the failure that cost a device session.
            note("declined: \(verdict.reason)")
            endedReason = verdict.reason
            chosenHost = nil
            phase = .joining
            return true
        }
        if let notice = LeaveNotice(bytes: bytes) {
            peerDeparted(peer, byHost: notice.byHost, announced: true)
            return true
        }
        if let update = RosterUpdate(bytes: bytes) {
            guard !isHost else { return true }  // the host is the source of truth
            roster = update.roster
            phase = .lobby
            return true
        }
        if let message = RaceStart(bytes: bytes) {
            guard !isHost else { return true }  // our own start, echoed back
            apply(message)
            return true
        }
        return false
    }

    /// **Race again with the same field.** The roster and the connection are
    /// already agreed, so a rematch is one fresh `RaceStart` — a new seed, the same
    /// everything else. Host only, and only from the lobby: mid-race it would yank
    /// the field out from under a race in progress.
    public func rematch(seed: UInt64) {
        // `canRematch` gates the button, so this repeats it — deliberately, because
        // a guest's `RaceStart` would start a race its host is not running, and a
        // future caller that skips the button must still be refused. Sabotaging
        // either guard alone leaves the other holding.
        guard isHost, start == nil, let course = lastCourse else { return }
        note("rematch: seed \(seed)")
        startRace(
            course: course, seed: seed, laps: CouchGame.networkedLaps,
            tuning: lastTuning)
    }

    /// Whether Rematch is available: the host, out of a race, with a course to
    /// repeat and somebody to race against.
    public var canRematch: Bool {
        isHost && start == nil && lastCourse != nil && roster.entries.count > 1
    }
}
