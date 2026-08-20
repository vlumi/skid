import Foundation
import Testing

@testable import SkidCore

/// **Pick your own color, first-come.** The claim rule lives in the core so the
/// host's roster and the couch's seat list resolve conflicts identically: the
/// preferred color when free, otherwise the free color that stays most distinct
/// from every claim already made — deterministically, because every device must
/// paint the same field without a die roll on the wire.
struct ColorClaimTests {
    @Test func aFreePreferenceIsGranted() {
        for wanted in 0..<CarPalette.count {
            #expect(CarPalette.claim(preferred: wanted, taken: []) == wanted)
            #expect(
                CarPalette.claim(
                    preferred: wanted, taken: Set(0..<CarPalette.count).subtracting([wanted]))
                    == wanted)
        }
    }

    @Test func aTakenPreferenceIsBumpedToAFreeColor() {
        for wanted in 0..<CarPalette.count {
            let granted = CarPalette.claim(preferred: wanted, taken: [wanted])
            #expect(granted != wanted, "the claim handed out a color somebody holds")
            #expect((0..<CarPalette.count).contains(granted))
        }
    }

    /// The replacement maximizes worst-case separation from the claims already
    /// made — the palette's own metric — NOT similarity to the preference, which
    /// would hand the bumped player the one color most confusable with the
    /// winner of the very conflict that bumped them.
    @Test func theReplacementStaysFarFromEveryClaim() {
        let taken: Set<Int> = [0, 1, 2]
        let granted = CarPalette.claim(preferred: 0, taken: taken)
        func worst(_ candidate: Int) -> Double {
            taken.reduce(.infinity) { nearest, held in
                CarPalette.Paint.Vision.allCases.reduce(nearest) { current, vision in
                    min(
                        current,
                        CarPalette.paints[candidate].seen(with: vision)
                            .distance(to: CarPalette.paints[held].seen(with: vision)))
                }
            }
        }
        let best = (0..<CarPalette.count).filter { !taken.contains($0) }.map(worst).max()
        #expect(worst(granted) == best, "the bump did not pick the best-separated free color")
    }

    /// Every device resolves the same claims to the same answer — the property
    /// that lets the host resolve once and everyone else trust the roster.
    @Test func claimsAreDeterministic() {
        for wanted in 0..<CarPalette.count {
            let taken: Set<Int> = [wanted, (wanted + 3) % CarPalette.count]
            let first = CarPalette.claim(preferred: wanted, taken: taken)
            for _ in 0..<10 {
                #expect(CarPalette.claim(preferred: wanted, taken: taken) == first)
            }
        }
    }

    // MARK: - The roster carries the claims

    @Test func theHostsPicksAlwaysHold() throws {
        var roster = RaceRoster()
        try roster.join("host#aaaa", seats: 2, colors: [3, 5])
        try roster.join("guest#bbbb", seats: 1, colors: [3])
        #expect(roster.entries[0].colors == [3, 5], "the host's claim was disturbed")
        let guest = roster.entries[1].colors
        #expect(guest.count == 1)
        #expect(guest[0] != 3, "the later claim took the host's color")
        #expect(guest[0] != 5)
    }

    /// Two guests wanting the same color: the earlier joiner keeps it, and ONLY
    /// the later one moves — never a shuffle of both.
    @Test func betweenGuestsTheEarlierJoinerKeepsTheColor() throws {
        var roster = RaceRoster()
        try roster.join("host#aaaa", seats: 1, colors: [0])
        try roster.join("early#bbbb", seats: 1, colors: [7])
        try roster.join("late#cccc", seats: 1, colors: [7])
        #expect(roster.entries[1].colors == [7], "the earlier claimant was shuffled")
        #expect(roster.entries[2].colors != [7], "two seats share a color")
        #expect(Set(roster.entries.flatMap(\.colors)).count == 3)
    }

    /// One device's own seats claim in local order, against each other too.
    @Test func oneDevicesSeatsCannotCollide() throws {
        var roster = RaceRoster()
        try roster.join("host#aaaa", seats: 3, colors: [4, 4, 4])
        let colors = roster.entries[0].colors
        #expect(colors[0] == 4, "the first local seat holds the pick")
        #expect(Set(colors).count == 3, "one device was granted duplicate colors")
    }

    /// No stated preference (an older build, or fewer picks than seats) defaults
    /// to seat-number colors — exactly what those builds display on their own.
    @Test func missingPreferencesDefaultToSeatColors() throws {
        var roster = RaceRoster()
        try roster.join("host#aaaa", seats: 2)
        #expect(roster.entries[0].colors == [0, 1])
        try roster.join("guest#bbbb", seats: 2, colors: [8])
        #expect(roster.entries[1].colors[0] == 8)
        #expect(roster.entries[1].colors[1] == 3, "seat 3's default is its seat number")
    }

    @Test func colorsLookUpBySeatWithASeatNumberFallback() throws {
        var roster = RaceRoster()
        try roster.join("host#aaaa", seats: 1, colors: [6])
        #expect(roster.colorIndex(forSeat: PlayerID(0)) == 6)
        // A seat the roster does not know falls back to its seat-number color.
        #expect(roster.colorIndex(forSeat: PlayerID(4)) == 4)
    }

    // MARK: - Mixed-version tolerance

    /// A roster encoded by a build that predates color claims decodes — the
    /// entry simply has no claims, and readers fall back to seat colors.
    @Test func anOldRosterEntryStillDecodes() throws {
        // An old build's bytes, made honestly: encode today's roster and strip
        // the key that build never wrote.
        var current = RaceRoster()
        try current.join("host#aaaa", seats: 2, colors: [5, 6])
        var json =
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(current)) as? [String: Any] ?? [:]
        var entries = json["entries"] as? [[String: Any]] ?? []
        entries[0].removeValue(forKey: "colors")
        json["entries"] = entries
        let old = try JSONSerialization.data(withJSONObject: json)

        let roster = try JSONDecoder().decode(RaceRoster.self, from: old)
        #expect(roster.entries[0].colors.isEmpty)
        #expect(roster.colorIndex(forSeat: PlayerID(1)) == 1, "no claims means seat colors")
    }

    /// An old build's join request (no colors field) still seats its players.
    @Test func anOldJoinRequestStillDecodes() throws {
        let bytes = [UInt8(201)] + [UInt8](Data("{\"seats\": 2}".utf8))
        let request = JoinRequest(bytes: bytes)
        #expect(request?.seats == 2)
        #expect(request?.colors.isEmpty == true)
    }

    @Test func aJoinRequestRoundTripsItsColors() {
        let request = JoinRequest(seats: 2, colors: [7, 2])
        let back = JoinRequest(bytes: request.encoded)
        #expect(back == request)
        #expect(back?.colors == [7, 2])
    }
}
