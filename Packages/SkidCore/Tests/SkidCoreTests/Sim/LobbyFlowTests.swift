import XCTest

@testable import SkidCore
@testable import SkidKit

/// The lobby handshake as a sequence of messages, without a radio. Two device
/// failures came out of this flow — a peer-name collision, then a countdown that
/// deadlocked — so the flow itself is now pinned.
final class LobbyFlowTests: XCTestCase {
    func testOnlyTheHostIsTheHostAfterARosterUpdate() {
        // A guest showing a working Start button means two devices can both try to
        // begin the race. Reported from device: the guest's Start rendered (and did
        // nothing), which is what a wrong `isHost` looks like.
        var hostRoster = RaceRoster()
        let host = "phoneA#aaaa"
        let guest = "phoneB#bbbb"
        try? hostRoster.join(host, seats: 2)
        try? hostRoster.join(guest, seats: 2)

        // What the guest receives and adopts.
        let update = RosterUpdate(roster: hostRoster)
        let received = try? XCTUnwrap(RosterUpdate(bytes: update.encoded)).roster
        let adopted = try? XCTUnwrap(received)

        XCTAssertEqual(adopted?.host, host, "the roster's first entry must be the host")
        XCTAssertNotEqual(adopted?.host, guest, "the guest would render a Start button")
        // And both devices agree on who drives what.
        XCTAssertEqual(adopted?.seats(for: host), [PlayerID(0), PlayerID(1)])
        XCTAssertEqual(adopted?.seats(for: guest), [PlayerID(2), PlayerID(3)])
        XCTAssertEqual(adopted?.seatCount, 4)
    }

    func testAGuestWithNoRosterYetIsNotTheHost() {
        // Before the first RosterUpdate the guest's roster is empty. `host` is nil
        // then, so `isHost` must be false rather than accidentally true.
        let empty = RaceRoster()
        XCTAssertNil(empty.host)
        XCTAssertNotEqual(empty.host, "anybody#0000")
    }

    func testTheStartMessageCarriesEverythingBothPeersNeed() {
        // Anything missing here is a divergence at tick 1 rather than an error, so
        // the round trip is worth asserting on the exact values.
        var roster = RaceRoster()
        try? roster.join("a#1111", seats: 2)
        try? roster.join("b#2222", seats: 1)
        let start = RaceStart(
            course: .builtin("clover"), seed: 12345, roster: roster, laps: 3, delayTicks: 2)

        guard let back = RaceStart(bytes: start.encoded) else {
            return XCTFail("the start message did not round-trip")
        }
        XCTAssertEqual(back, start)
        XCTAssertEqual(back.seed, 12345)
        XCTAssertEqual(back.roster.seats, roster.seats)
        XCTAssertEqual(back.delayTicks, 2)
        if case .builtin(let id) = back.course {
            XCTAssertEqual(id, "clover")
        } else {
            XCTFail("the course changed kind in transit")
        }
    }

    func testASharedTrackTravelsAsItsCode() {
        // A guest may never have seen the host's custom track — carrying the share
        // code rather than an id is what makes that work at all.
        var roster = RaceRoster()
        try? roster.join("a#1111", seats: 1)
        let code = TrackCode.encode(TrackLibrary.layout(id: "eight") ?? TrackLayout(pieces: []))
        let start = RaceStart(
            course: .shared(code), seed: 7, roster: roster, laps: 3, delayTicks: 2)
        guard let back = RaceStart(bytes: start.encoded), case .shared(let got) = back.course
        else { return XCTFail("a shared course did not survive") }
        XCTAssertEqual(got, code)
        // And it still decodes into a raceable track on the far side.
        XCTAssertNotNil(try? TrackCode.decode(got))
    }

    @MainActor
    func testTwoPlayersSitFaceToFaceByDefault() {
        // What two people actually do with a phone flat on a table: one either
        // side, each with a full-width band and their own "up". Side-by-side halves
        // each player's control room — cramped on an iPhone — and exists to cram
        // three or four players onto one screen, not because two players want it.
        XCTAssertTrue(CouchGame().faceToFace, "two players default to side-by-side")
    }

    func testAMalformedLobbyMessageIsRejected() {
        XCTAssertNil(RaceStart(bytes: []))
        XCTAssertNil(RaceStart(bytes: [200]))
        XCTAssertNil(RaceStart(bytes: [200, 1, 2, 3]))
        XCTAssertNil(RosterUpdate(bytes: [202, 9]))
        XCTAssertNil(JoinRequest(bytes: [201, 9]))
        // A lobby message must not be mistaken for a different kind.
        var roster = RaceRoster()
        try? roster.join("a#1111", seats: 1)
        let update = RosterUpdate(roster: roster).encoded
        XCTAssertNil(RaceStart(bytes: update), "a roster decoded as a start")
        XCTAssertNil(JoinRequest(bytes: update), "a roster decoded as a join request")
    }
}
