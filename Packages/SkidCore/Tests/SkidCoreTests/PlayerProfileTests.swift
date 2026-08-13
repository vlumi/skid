import Foundation
import Testing

@testable import SkidCore

/// **Identity, and the rule that not having one is fine.**
///
/// The design's load-bearing claim is that a guest is a full player who simply has
/// nowhere to write results. These pin that, plus the book's tolerant decode — the
/// property that keeps a future format from eating someone's profiles.
struct PlayerProfileTests {
    /// A guest has no id, and every record-keeping path is written as
    /// `guard let id = seat.profileID`. If this ever returned something non-nil, a
    /// guest's lap would be filed against a profile that did not consent to it.
    @Test func aGuestHasNothingToRecordAgainst() {
        #expect(SeatIdentity.guest.profileID == nil)
        let id = UUID()
        #expect(SeatIdentity.profile(id).profileID == id)
    }

    /// **A rename must not orphan records.** They are keyed by id, so the id has to
    /// survive a name change — which is the reason a profile is not keyed by name.
    @Test func renamingKeepsTheIdentity() {
        var book = ProfileBook()
        var sam = PlayerProfile(name: "Sam", colorIndex: 0)
        _ = book.put(sam)
        sam.name = "Samantha"
        _ = book.put(sam)
        #expect(book.profiles.count == 1, "a rename made a second profile")
        #expect(book.profile(id: sam.id)?.name == "Samantha")
    }

    /// Two people with the same name are allowed. Refusing the second would be worse
    /// than the ambiguity, and the id keeps them distinct where it matters.
    @Test func twoProfilesMayShareAName() {
        var book = ProfileBook()
        _ = book.put(PlayerProfile(name: "Sam", colorIndex: 0))
        _ = book.put(PlayerProfile(name: "Sam", colorIndex: 1))
        #expect(book.profiles.count == 2)
    }

    /// Names are cleaned, and whitespace is not a name. Nil is the honest answer —
    /// the caller's response is "stay a guest", which needs no invented text.
    @Test func aNameOfNothingIsNotAName() {
        #expect(PlayerProfile.cleaned(name: "") == nil)
        #expect(PlayerProfile.cleaned(name: "   \n ") == nil)
        #expect(PlayerProfile.cleaned(name: "  Sam  ") == "Sam")
    }

    /// Long names are capped rather than refused, so a paste does not fail — but the
    /// cap has to actually bite, or a standings row can be pushed off screen.
    @Test func aLongNameIsCappedNotRefused() {
        let long = String(repeating: "a", count: 100)
        let cleaned = PlayerProfile.cleaned(name: long)
        #expect(cleaned?.count == PlayerProfile.maxNameLength)
    }

    /// The cap stops NEW profiles, never an update to an existing one — a full book
    /// that could not be edited would be a trap.
    @Test func afullBookStillAcceptsEdits() {
        var book = ProfileBook()
        for index in 0..<ProfileBook.maxProfiles {
            let added = book.put(PlayerProfile(name: "P\(index)", colorIndex: 0))
            #expect(added)
        }
        let overflowed = book.put(PlayerProfile(name: "one too many", colorIndex: 0))
        #expect(!overflowed)

        var existing = book.profiles[0]
        existing.name = "renamed"
        let edited = book.put(existing)
        #expect(edited, "a full book refused an edit to a profile it holds")
        #expect(book.profile(id: existing.id)?.name == "renamed")
        #expect(book.profiles.count == ProfileBook.maxProfiles)
    }

    /// Recency ordering puts whoever played last at the top of a picker. Dates are
    /// injected rather than taken from the clock, so the test is not a race.
    @Test func theMostRecentPlayerComesFirst() {
        var book = ProfileBook()
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        _ = book.put(
            PlayerProfile(name: "old", colorIndex: 0, createdAt: old, lastPlayedAt: old))
        _ = book.put(
            PlayerProfile(name: "new", colorIndex: 1, createdAt: old, lastPlayedAt: new))
        #expect(book.byRecency.map(\.name) == ["new", "old"])
    }

    /// A profile that has never played falls back to its creation date, so a brand-new
    /// one is not buried under everyone who has.
    @Test func aNeverPlayedProfileSortsByWhenItWasMade() {
        var book = ProfileBook()
        let long = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 5_000)
        _ = book.put(
            PlayerProfile(name: "veteran", colorIndex: 0, createdAt: long, lastPlayedAt: long))
        _ = book.put(PlayerProfile(name: "fresh", colorIndex: 1, createdAt: recent))
        #expect(book.byRecency.first?.name == "fresh")
    }

    /// **A future format must not eat existing profiles.** Same tolerant-decode
    /// contract as `HiscoreBook`: unknown version → nil, and the caller starts fresh
    /// rather than crashing on someone's data.
    @Test func aFutureVersionDecodesToNil() throws {
        var book = ProfileBook()
        _ = book.put(PlayerProfile(name: "Sam", colorIndex: 0))
        var data = try book.encoded()
        #expect(ProfileBook.decode(data) != nil)

        book.version = ProfileBook.currentVersion + 1
        data = try book.encoded()
        #expect(ProfileBook.decode(data) == nil, "a newer book was read as if understood")
    }

    /// Round-trips, including the seat identity — a guest must survive encoding as a
    /// guest rather than as a profile with a zero id.
    @Test func identitiesRoundTrip() throws {
        for identity in [SeatIdentity.guest, .profile(UUID())] {
            let data = try JSONEncoder().encode(identity)
            let back = try JSONDecoder().decode(SeatIdentity.self, from: data)
            #expect(back == identity)
        }
    }

    @Test func markingPlayedMovesAProfileUp() {
        var book = ProfileBook()
        let first = PlayerProfile(
            name: "first", colorIndex: 0, createdAt: Date(timeIntervalSince1970: 9_000))
        let second = PlayerProfile(
            name: "second", colorIndex: 1, createdAt: Date(timeIntervalSince1970: 1_000))
        _ = book.put(first)
        _ = book.put(second)
        #expect(book.byRecency.first?.name == "first")

        book.markPlayed(id: second.id, at: Date(timeIntervalSince1970: 10_000))
        #expect(book.byRecency.first?.name == "second")
    }
}

/// **The field list's own invariants**, separately from the game object that uses it.
///
/// Added because coverage found four untested paths in `RaceEntrant` — including
/// `nonEmpty`'s guard, which is the one that keeps a race from having nobody in it.
struct RaceFieldTests {
    /// A row identifies itself, and two guests deliberately collide: they are the same
    /// thing, so the list is enumerated by index as well.
    @Test func rowIdsDistinguishPlayersButNotGuests() {
        let sam = UUID()
        #expect(RaceEntrant.guest.id == RaceEntrant.guest.id)
        #expect(RaceEntrant.profile(sam).id != RaceEntrant.guest.id)
        #expect(RaceEntrant.profile(sam).id != RaceEntrant.profile(UUID()).id)
    }

    /// The seat view of a row, which is what the records layer reads.
    @Test func everyRowPresentsASeatIdentity() {
        let sam = UUID()
        #expect(RaceEntrant.guest.seatIdentity == .guest)
        #expect(RaceEntrant.profile(sam).seatIdentity == .profile(sam))
        #expect(RaceEntrant.guest.kind == .guest)
        #expect(RaceEntrant.profile(sam).kind == .player)
        #expect(RaceEntrant.guest.profileID == nil)
        #expect(RaceEntrant.profile(sam).profileID == sam)
    }

    /// **A race must have somebody in it.** The guard is the whole point: an empty list
    /// would be a field of no cars, which is not a state worth being able to reach.
    @Test func anEmptyListGetsAPersonBack() {
        #expect(RaceField.nonEmpty([]).count == 1)
        #expect(RaceField.nonEmpty([]) == [.guest])
        // …and a list that already has somebody is left exactly as it was.
        let sam = RaceEntrant.profile(UUID())
        #expect(RaceField.nonEmpty([sam]) == [sam])
        #expect(RaceField.nonEmpty([.guest, sam]) == [.guest, sam])
    }

    /// Capping trims to the capacity, and never below one — a zero would empty a list
    /// whose floor is one person.
    @Test func cappingNeverEmptiesTheList() {
        let rows: [RaceEntrant] = [.guest, .guest, .guest, .guest]
        #expect(RaceField.capped(rows, to: 2).count == 2)
        #expect(RaceField.capped(rows, to: 9).count == 4, "capping invented rows")
        #expect(RaceField.capped(rows, to: 0).count == 1)
        #expect(RaceField.capped(rows, to: -5).count == 1)
    }

    @Test func humansAreCounted() {
        #expect(RaceField.humanCount([]) == 0)
        #expect(RaceField.humanCount([.guest, .profile(UUID())]) == 2)
    }
}
