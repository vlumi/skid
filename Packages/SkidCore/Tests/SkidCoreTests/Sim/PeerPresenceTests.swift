import XCTest

@testable import SkidCore

/// The grace period. MultipeerConnectivity reports a peer lost on brief
/// interruptions, so the failure mode that matters here is ejecting a player for
/// a hiccup — worse than a car that coasts for a second.
final class PeerPresenceTests: XCTestCase {
    func testABriefDropDoesNotEjectAnyone() {
        // The whole point of the type. Down and back inside the grace period is a
        // non-event: nobody leaves, nothing is announced.
        var presence = PeerPresence()
        presence.lost("guest#bbbb")
        XCTAssertTrue(presence.isFading("guest#bbbb"))
        XCTAssertFalse(presence.hasDeparted("guest#bbbb"))

        XCTAssertEqual(presence.advance(by: PeerPresence.grace - 0.5), [])
        XCTAssertTrue(presence.recovered("guest#bbbb"), "the return was not noticed")
        XCTAssertFalse(presence.isFading("guest#bbbb"))
        // And time passing afterwards must not eject them retroactively.
        XCTAssertEqual(presence.advance(by: 10), [])
        XCTAssertFalse(presence.hasDeparted("guest#bbbb"))
    }

    func testAlossThatOutlastsTheGraceIsFinal() {
        var presence = PeerPresence()
        presence.lost("guest#bbbb")
        XCTAssertEqual(presence.advance(by: PeerPresence.grace), ["guest#bbbb"])
        XCTAssertTrue(presence.hasDeparted("guest#bbbb"))
        XCTAssertFalse(presence.isFading("guest#bbbb"), "a departed peer is not still fading")
    }

    func testAnExpiryIsReportedExactlyOnce() {
        // Callers act on the transition (announce it, coast the car), so a repeat
        // would announce a departure every frame for the rest of the race.
        var presence = PeerPresence()
        presence.lost("a")
        XCTAssertEqual(presence.advance(by: PeerPresence.grace), ["a"])
        XCTAssertEqual(presence.advance(by: PeerPresence.grace), [])
        XCTAssertEqual(presence.advance(by: 100), [])
    }

    func testAFlappingLinkCannotResurrectADepartedPeer() {
        // **No mid-race rejoin, decided.** A link that comes back after the grace
        // must not put the player's car back on the track from a stale position —
        // they are out, and out means out.
        var presence = PeerPresence()
        presence.lost("gone")
        _ = presence.advance(by: PeerPresence.grace)
        XCTAssertFalse(presence.recovered("gone"), "a departed peer came back")
        // And it is still departed AFTER the attempted recovery — the guard has to
        // hold the state, not just report false. Asserting only the return value
        // passed with the guard removed, since a departed peer has no fading entry
        // to remove either way.
        XCTAssertTrue(presence.hasDeparted("gone"))
        XCTAssertEqual(presence.departedPeers, ["gone"])
        // A recovery followed by another loss is the realistic flap, and it must
        // still not resurrect them.
        presence.lost("gone")
        _ = presence.recovered("gone")
        XCTAssertTrue(presence.hasDeparted("gone"), "a flap resurrected a departed peer")
        XCTAssertFalse(presence.isFading("gone"), "a departed peer started fading again")
        XCTAssertEqual(presence.advance(by: PeerPresence.grace), [], "it expired twice")
    }

    func testSeveralPeersFadeOnTheirOwnClocks() {
        // Each peer's grace runs from its own loss, so a later drop must not
        // inherit an earlier one's elapsed time.
        var presence = PeerPresence()
        presence.lost("early")
        XCTAssertEqual(presence.advance(by: PeerPresence.grace - 0.5), [])
        presence.lost("late")
        // Half a second more finishes `early` and leaves `late` with most of its
        // grace still to run.
        XCTAssertEqual(presence.advance(by: 0.5), ["early"])
        XCTAssertTrue(presence.isFading("late"))
        XCTAssertFalse(presence.hasDeparted("late"))
        XCTAssertEqual(presence.advance(by: PeerPresence.grace), ["late"])
    }

    func testPresenceIsReadableAgainstARoster() {
        var roster = RaceRoster()
        try? roster.join("host#aaaa", seats: 1)
        try? roster.join("fader#bbbb", seats: 1)
        try? roster.join("goner#cccc", seats: 1)
        var presence = PeerPresence()
        presence.lost("fader#bbbb")
        presence.lost("goner#cccc")
        XCTAssertEqual(presence.advance(by: PeerPresence.grace - 0.1), [])
        presence.recovered("fader#bbbb")
        presence.lost("goner#cccc")  // still down
        XCTAssertEqual(presence.advance(by: PeerPresence.grace), ["goner#cccc"])

        // Roster order, not alphabetical — the host is first and seats follow join
        // order, which is what any list on screen should show.
        XCTAssertEqual(presence.present(in: roster), ["host#aaaa", "fader#bbbb"])
        XCTAssertEqual(presence.departedPeers, ["goner#cccc"])
        XCTAssertEqual(presence.fadingPeers, [])
    }

    func testAFreshRaceForgetsLastRacesDepartures() {
        // Rematch reuses the connection, so last race's casualties must not be
        // written off before the new one starts.
        var presence = PeerPresence()
        presence.lost("guest#bbbb")
        _ = presence.advance(by: PeerPresence.grace)
        XCTAssertTrue(presence.hasDeparted("guest#bbbb"))
        presence.reset()
        XCTAssertFalse(presence.hasDeparted("guest#bbbb"))
        XCTAssertEqual(presence.departedPeers, [])
        // And they can fade normally again.
        presence.lost("guest#bbbb")
        XCTAssertTrue(presence.isFading("guest#bbbb"))
    }

    func testTheGraceIsLongEnoughForAHiccupAndShortEnoughForARace() {
        // Both halves of the choice, pinned: a spurious MC loss is sub-second, and
        // a short race is ~30 s, so waiting a tenth of it is the ceiling.
        XCTAssertGreaterThanOrEqual(PeerPresence.grace, 2)
        XCTAssertLessThanOrEqual(PeerPresence.grace, 5)
    }
}
