import XCTest

@testable import SkidCore
@testable import SkidKit

/// The session loop, driven through two real `NetworkedGame`s: join on purpose,
/// race, leave, race again. Force-quitting between races is what this exists to
/// end, so the test that matters most is the one that plays two races over one
/// connection.
@MainActor
final class SessionLoopTests: XCTestCase {
    private let hostKey = "host#aaaa"
    private let guestKey = "guest#bbbb"

    /// Two games wired to each other, with delivery under the test's control.
    @MainActor
    private struct Pair {
        let host: NetworkedGame
        let guest: NetworkedGame

        /// Deliver everything each side has queued, until both are quiet — the
        /// lobby handshake is several reliable round trips.
        func settle(rounds: Int = 6) {
            for _ in 0..<rounds {
                let fromHost = host.drainOutbox()
                let fromGuest = guest.drainOutbox()
                if fromHost.isEmpty, fromGuest.isEmpty { return }
                for bytes in fromHost { guest.deliverForTesting(bytes, from: "host#aaaa") }
                for bytes in fromGuest { host.deliverForTesting(bytes, from: "guest#bbbb") }
            }
        }
    }

    private func lobbyPair(hostSeats: Int = 1, guestSeats: Int = 1) -> Pair {
        let host = NetworkedGame(displayName: hostKey)
        let guest = NetworkedGame(displayName: guestKey)
        host.captureSendsForTesting()
        guest.captureSendsForTesting()
        host.host(seats: hostSeats)
        guest.join(seats: guestSeats)
        // Discovery, both directions.
        guest.transport(peerJoined: hostKey)
        host.transport(peerJoined: guestKey)
        return Pair(host: host, guest: guest)
    }

    // MARK: - Joining on purpose

    func testAGuestPicksAHostRatherThanTakingTheFirstOne() {
        // The spike joined whatever answered first; in a room with two races that
        // is a coin toss.
        let pair = lobbyPair()
        XCTAssertEqual(pair.guest.phase, .joining)
        XCTAssertEqual(pair.guest.visibleHosts, [hostKey])
        // Seeing a second race must not join it either.
        pair.guest.transport(peerJoined: "other-host#cccc")
        XCTAssertEqual(pair.guest.visibleHosts, [hostKey, "other-host#cccc"])
        XCTAssertEqual(pair.guest.phase, .joining, "a guest joined without choosing")
        XCTAssertTrue(pair.host.pendingJoins.isEmpty, "asked to join without being told to")

        pair.guest.askToJoin(hostKey)
        XCTAssertEqual(pair.guest.phase, .awaitingApproval)
        pair.settle()
        XCTAssertEqual(pair.host.pendingJoins.map(\.peer), [guestKey])
        XCTAssertEqual(pair.host.roster.entries.count, 1, "seated before the host approved")
    }

    func testTheHostApprovesAndTheRosterReachesTheGuest() {
        let pair = lobbyPair(hostSeats: 2, guestSeats: 2)
        pair.guest.askToJoin(hostKey)
        pair.settle()
        pair.host.approve(guestKey)
        pair.settle()

        XCTAssertEqual(pair.host.roster.seatCount, 4)
        XCTAssertEqual(pair.guest.roster.seatCount, 4, "the guest never got the roster")
        XCTAssertEqual(pair.guest.phase, .lobby)
        XCTAssertEqual(pair.guest.roster.seats(for: guestKey).map(\.rawValue), [2, 3])
        XCTAssertTrue(pair.host.pendingJoins.isEmpty)
        // Exactly one host, on both sides.
        XCTAssertTrue(pair.host.isHost)
        XCTAssertFalse(pair.guest.isHost)
    }

    func testADeclinedGuestIsToldWhyAndGoesBackToBrowsing() {
        // A refusal that showed nothing was the failure that cost a device session.
        let pair = lobbyPair()
        pair.guest.askToJoin(hostKey)
        pair.settle()
        pair.host.decline(guestKey)
        pair.settle()

        XCTAssertEqual(pair.guest.phase, .joining, "a declined guest is stuck waiting")
        XCTAssertNotNil(pair.guest.endedReason, "declined in silence")
        XCTAssertEqual(pair.host.roster.entries.count, 1)
        XCTAssertTrue(pair.host.pendingJoins.isEmpty)
        // And it can ask again — a decline is not a ban.
        pair.guest.askToJoin(hostKey)
        pair.settle()
        XCTAssertEqual(pair.host.pendingJoins.map(\.peer), [guestKey])
    }

    // MARK: - The loop that ends the restarts

    func testTwoRacesOverOneConnection() {
        // **The point of the whole commit.** Race, finish, race again — without
        // rejoining, and without the roster or the connection being rebuilt.
        let pair = lobbyPair()
        pair.guest.askToJoin(hostKey)
        pair.settle()
        pair.host.approve(guestKey)
        pair.settle()

        pair.host.startRace(course: .builtin("small"), seed: 1, laps: 3)
        pair.settle()
        XCTAssertEqual(pair.host.phase, .racing)
        XCTAssertEqual(pair.guest.phase, .racing, "the guest never started")

        // Race over: back to the lobby on both sides, connection intact.
        pair.host.returnToLobby()
        pair.guest.returnToLobby()
        XCTAssertEqual(pair.host.phase, .hosting, "the host is not back in its lobby")
        // The radio stayed on for the whole session — tearing the advertiser down
        // mid-handshake dropped the MC session during the spike, so it is never
        // stopped. A findable lobby between races is the payoff.
        XCTAssertTrue(pair.host.isAdvertisingForTesting, "the host is unfindable")
        XCTAssertEqual(pair.guest.phase, .lobby)
        XCTAssertEqual(pair.host.roster.seatCount, 2, "the field was lost between races")
        XCTAssertTrue(pair.host.canRematch, "rematch unavailable with a full lobby")

        // And again — one message, no new decisions.
        pair.host.rematch(seed: 2)
        pair.settle()
        XCTAssertEqual(pair.host.phase, .racing)
        XCTAssertEqual(pair.guest.phase, .racing, "the guest missed the rematch")
    }

    func testRematchNeedsAHostOutOfARaceWithSomebodyToRaceAgainst() {
        let pair = lobbyPair()
        // Nobody has joined: nothing to rematch.
        XCTAssertFalse(pair.host.canRematch)
        pair.guest.askToJoin(hostKey)
        pair.settle()
        pair.host.approve(guestKey)
        pair.settle()
        // Still nothing to REPEAT until a race has happened.
        XCTAssertFalse(pair.host.canRematch, "rematched a race that never ran")

        pair.host.startRace(course: .builtin("small"), seed: 1, laps: 3)
        pair.settle()
        // Mid-race a rematch would yank the field out from under a running race.
        XCTAssertFalse(pair.host.canRematch)
        pair.host.rematch(seed: 9)
        XCTAssertEqual(pair.host.phase, .racing)

        pair.host.returnToLobby()
        XCTAssertTrue(pair.host.canRematch)
        // **A guest may not start races**, and the check has to be `isHost` rather
        // than "has a course to repeat": a guest DOES learn the course from the
        // start message, so after one race it has everything but the authority.
        // Out of the race and holding the course it just raced — everything a host
        // would need — so `isHost` is the only thing refusing it here.
        pair.guest.returnToLobby()
        XCTAssertFalse(pair.guest.canRematch, "a guest offered a rematch")
        _ = pair.guest.drainOutbox()
        pair.guest.rematch(seed: 7)
        XCTAssertEqual(pair.guest.phase, .lobby, "a guest started a race")
        XCTAssertTrue(pair.guest.drainOutbox().isEmpty, "a guest sent a start message")
        // And the host still can, from the same state — so the refusal is about
        // authority, not about a missing course.
        XCTAssertTrue(pair.host.canRematch)
    }

    // MARK: - Leaving

    func testAGuestLeavingCostsItsOwnCarsOnly() {
        let pair = lobbyPair()
        pair.guest.askToJoin(hostKey)
        pair.settle()
        pair.host.approve(guestKey)
        pair.settle()
        pair.host.startRace(course: .builtin("small"), seed: 1, laps: 3)
        pair.settle()

        pair.guest.leave()
        pair.settle()
        XCTAssertEqual(pair.guest.phase, .idle)
        // The host's race carries on — that is the model's point.
        XCTAssertEqual(pair.host.phase, .racing, "a guest leaving ended the host's race")
        XCTAssertNotNil(pair.host.stallNote, "the host was not told the guest left")
    }

    func testTheHostLeavingEndsTheRaceForEveryone() {
        // There is no race without the device simulating it, so this is not a
        // stall to wait out — it is over, and it should say so.
        let pair = lobbyPair()
        pair.guest.askToJoin(hostKey)
        pair.settle()
        pair.host.approve(guestKey)
        pair.settle()
        pair.host.startRace(course: .builtin("small"), seed: 1, laps: 3)
        pair.settle()

        pair.host.leave()
        pair.settle()
        guard case .ended(let reason) = pair.guest.phase else {
            return XCTFail("the guest is still in phase \(pair.guest.phase)")
        }
        XCTAssertNotNil(reason, "the race ended with no reason on screen")
        XCTAssertEqual(pair.guest.roster.seatCount, 0)
    }

    // MARK: - Dropping

    func testABriefDropDoesNotEjectAPlayerMidRace() {
        // The care the maintainer asked for: MC reports a peer lost on short
        // interruptions, and ejecting somebody for a hiccup is the failure that
        // matters. The car holds its last input and the screen says so.
        let pair = lobbyPair()
        pair.guest.askToJoin(hostKey)
        pair.settle()
        pair.host.approve(guestKey)
        pair.settle()
        pair.host.startRace(course: .builtin("small"), seed: 1, laps: 3)
        pair.settle()

        pair.host.transport(peerLeft: guestKey)
        XCTAssertEqual(pair.host.phase, .racing)
        // Fading, not gone — and the wording is the difference a player sees.
        XCTAssertEqual(pair.host.stallNote, "guest is dropping out…")
        pair.host.noteTime(PeerPresence.grace - 0.5)
        XCTAssertEqual(pair.host.stallNote, "guest is dropping out…", "declared gone too early")
        XCTAssertEqual(pair.host.roster.seatCount, 2, "ejected inside the grace period")

        // Back in time: a non-event, and never announced as a departure.
        pair.host.transport(peerJoined: guestKey)
        pair.host.noteTime(PeerPresence.grace * 2)
        XCTAssertEqual(pair.host.roster.seatCount, 2, "ejected after recovering")
        XCTAssertNotEqual(
            pair.host.stallNote, "guest dropped out", "announced a recovery as a loss")
    }

    func testADropThatOutlastsTheGraceIsFinalAndTheRaceGoesOn() {
        let pair = lobbyPair()
        pair.guest.askToJoin(hostKey)
        pair.settle()
        pair.host.approve(guestKey)
        pair.settle()
        pair.host.startRace(course: .builtin("small"), seed: 1, laps: 3)
        pair.settle()

        // A newcomer asking mid-race is refused: every device built its race from
        // this roster, so changing it would leave them disagreeing about the field.
        // Two guards do this — the receive path drops the request, and `seat` would
        // refuse it anyway — and only the first is reachable, which is why sabotaging
        // the second changes nothing. That is belt and braces on the field's
        // integrity, and the comment there says so.
        pair.host.deliverForTesting(JoinRequest(seats: 1).encoded, from: "latecomer#dddd")
        XCTAssertEqual(pair.host.roster.seatCount, 2, "seated a newcomer mid-race")
        XCTAssertTrue(pair.host.pendingJoins.isEmpty, "queued a mid-race join")
        // Directly, too: the inner guard holds on its own.
        pair.host.seat("latecomer#dddd", seats: 1)
        XCTAssertEqual(pair.host.roster.seatCount, 2, "seat() ignored the frozen roster")

        pair.host.transport(peerLeft: guestKey)
        pair.host.noteTime(PeerPresence.grace)
        // Mid-race the roster stays FROZEN — every device built its race from it —
        // so the cars coast and the field changes at the next race.
        XCTAssertEqual(pair.host.phase, .racing, "a drop ended the host's race")
        XCTAssertEqual(pair.host.roster.seatCount, 2, "the roster changed mid-race")
        // Now it IS a departure, and says so — the transition is what a player reads.
        XCTAssertEqual(pair.host.stallNote, "guest dropped out")

        // Next race: the departed guest is not in the field.
        pair.host.returnToLobby()
        XCTAssertEqual(pair.host.roster.seatCount, 2)
    }

    func testALobbyDropIsImmediateSinceNobodyIsMidCorner() {
        let pair = lobbyPair()
        pair.guest.askToJoin(hostKey)
        pair.settle()
        pair.host.approve(guestKey)
        pair.settle()
        XCTAssertEqual(pair.host.roster.seatCount, 2)

        pair.host.transport(peerLeft: guestKey)
        XCTAssertEqual(pair.host.roster.seatCount, 1, "a lobby drop waited out the grace")
        XCTAssertFalse(pair.host.canRematch)
    }

    func testARematchGivesTheClientAFreshRigAndSession() {
        // **Reported from device: after a rematch the client's controls did nothing.**
        // A client is never asked about the next race — it receives a `RaceStart` —
        // so its rig and session are replaced underneath a screen that never left
        // `.racing`. Anything the view still holds from the previous race is dead
        // wiring: the pad the player can see drives a session nobody advances.
        let pair = lobbyPair()
        pair.guest.askToJoin(hostKey)
        pair.settle()
        pair.host.approve(guestKey)
        pair.settle()

        let game = CouchGame()
        pair.guest.onStart { start in game.startNetworkedRace(start, driver: pair.guest) }

        pair.host.startRace(course: .builtin("small"), seed: 1, laps: 3)
        pair.settle()
        let firstRig = game.rig
        let firstSession = game.session
        XCTAssertNotNil(firstRig)
        XCTAssertEqual(firstSession?.generation, 1)

        // The host races again; the client only learns via the message.
        pair.host.returnToLobby()
        pair.host.rematch(seed: 2)
        pair.settle()

        // Both must be new, and the SESSION must be the one the view will drive.
        XCTAssertFalse(firstSession === game.session, "the client reused the old session")
        XCTAssertFalse(firstRig === game.rig, "the client reused the old rig")
        XCTAssertEqual(game.session?.generation, 2, "the new session is stamped for the old race")
        XCTAssertEqual(game.session?.generation, pair.guest.generation)
        // And the new rig drives this device's seat, not the host's.
        XCTAssertEqual(game.rig?.players.map(\.player), pair.guest.mySeats)
        XCTAssertEqual(game.phase, .racing)
    }
}
