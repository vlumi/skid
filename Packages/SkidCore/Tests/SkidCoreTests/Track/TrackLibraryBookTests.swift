import XCTest

@testable import SkidCore

/// The library that replaces the single "My track" slot.
final class TrackLibraryBookTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(
        _ name: String, code: String = TestTracks.Code.bridgeRing, at offset: TimeInterval = 0
    ) -> TrackLibraryBook.Entry {
        TrackLibraryBook.Entry(
            name: name, code: code,
            createdAt: epoch.addingTimeInterval(offset),
            updatedAt: epoch.addingTimeInterval(offset))
    }

    func testRoundTripsThroughJSON() throws {
        var book = TrackLibraryBook()
        book.put(entry("Mine"))
        var imported = entry("Theirs", code: TestTracks.Code.clover, at: 60)
        imported.authorKey = Array(repeating: 7, count: 32)
        imported.signatureIsValid = true
        imported.importedAt = epoch.addingTimeInterval(60)
        book.put(imported)

        let back = try XCTUnwrap(TrackLibraryBook.decode(book.encoded()))
        XCTAssertEqual(back, book)
        XCTAssertEqual(back.tracks.count, 2)
        XCTAssertNil(back.tracks[0].authorKey)
        XCTAssertEqual(back.tracks[1].authorKey?.count, 32)
        XCTAssertTrue(back.tracks[1].isImported)
        XCTAssertFalse(back.tracks[0].isImported)
    }

    /// A book from a newer build is refused rather than half-read.
    func testAFutureVersionIsRefused() throws {
        var book = TrackLibraryBook()
        book.put(entry("Mine"))
        book.version = TrackLibraryBook.currentVersion + 1
        XCTAssertNil(TrackLibraryBook.decode(try book.encoded()))
    }

    /// **Identity is the code, not the name.** Two different roads called the
    /// same thing are two tracks; the name is only for humans.
    func testTwoTracksMayShareAName() {
        var book = TrackLibraryBook()
        let first = entry("Hairpin")
        let second = entry("Hairpin", code: TestTracks.Code.clover)
        book.put(first)
        book.put(second)

        XCTAssertEqual(book.tracks.count, 2)
        XCTAssertEqual(book.entry(id: first.id)?.code, TestTracks.Code.bridgeRing)
        XCTAssertEqual(book.entry(id: second.id)?.code, TestTracks.Code.clover)
        XCTAssertNotEqual(first.trackID, second.trackID)
    }

    /// **The same road is the same entry**, however it arrived. Re-importing a
    /// code you already have must not leave two rows for one track.
    func testTheSameCodeIsTheSameEntry() {
        var book = TrackLibraryBook()
        book.put(entry("Mine"))
        book.put(entry("Mine again", at: 500))

        XCTAssertEqual(book.tracks.count, 1)
        XCTAssertEqual(book.tracks[0].name, "Mine again")
        XCTAssertTrue(book.contains(code: TestTracks.Code.bridgeRing))
        XCTAssertFalse(book.contains(code: TestTracks.Code.clover))
    }

    /// A SIGNED share of a track is the same track. The signature rides with
    /// the sharer, not with the road.
    func testASignedShareIsTheSameEntry() throws {
        let key = InMemorySigningKey()
        let layout = try TrackCode.decode(TestTracks.Code.bridgeRing)
        let signed = try TrackCode.encode(layout, signedBy: key)

        var book = TrackLibraryBook()
        book.put(entry("Unsigned"))
        book.put(entry("Signed", code: signed, at: 500))

        XCTAssertEqual(book.tracks.count, 1, "signing must not fork the identity")
        XCTAssertTrue(book.contains(code: signed))
        XCTAssertEqual(TrackCode.contentCode(of: signed), TrackCode.encode(layout))
    }

    /// **A future envelope section must not fork the identity.** The rule is
    /// the tag range, not a list of known envelope tags — so a section nobody
    /// has written yet (a name riding along, say) is excluded by default rather
    /// than silently making one road into two library rows.
    func testAnUnknownEnvelopeSectionDoesNotForkTheIdentity() throws {
        let layout = try TrackCode.decode(TestTracks.Code.bridgeRing)
        var body = TrackCode.encodedBody(layout)
        TrackCode.appendSection(&body, .pubkey, Array(repeating: 9, count: 32))
        let withEnvelope = TrackCode.finish(body)

        XCTAssertNotEqual(withEnvelope, TestTracks.Code.bridgeRing, "the bytes differ")
        XCTAssertEqual(
            TrackCode.contentCode(of: withEnvelope), TestTracks.Code.bridgeRing,
            "but the road — and so the identity — is the same")

        var book = TrackLibraryBook()
        book.put(entry("Plain"))
        book.put(entry("With envelope", code: withEnvelope, at: 10))
        XCTAssertEqual(book.tracks.count, 1)
    }

    /// Editing a track makes it a different road, so it is a different entry —
    /// and its times start fresh, which is the honest answer.
    func testAnEditedTrackIsADifferentEntry() {
        var book = TrackLibraryBook()
        book.put(entry("Before"))
        book.put(entry("After", code: TestTracks.Code.clover, at: 10))
        XCTAssertEqual(book.tracks.count, 2)
    }

    /// A rename keeps the identity, so hiscores survive it.
    func testRenamingKeepsTheIdentity() {
        var book = TrackLibraryBook()
        let original = entry("Draft")
        book.put(original)
        var renamed = original
        renamed.name = "Final"
        book.put(renamed)

        XCTAssertEqual(book.tracks.count, 1)
        XCTAssertEqual(book.entry(id: original.id)?.name, "Final")
        XCTAssertEqual(renamed.trackID, original.trackID)
    }

    func testRecencyOrdersNewestFirst() {
        var book = TrackLibraryBook()
        book.put(entry("old", code: TestTracks.Code.bridgeRing, at: 0))
        book.put(entry("newest", code: TestTracks.Code.clover, at: 200))
        book.put(entry("middle", code: TestTracks.Code.cloverOpen, at: 100))
        XCTAssertEqual(book.byRecency.map(\.name), ["newest", "middle", "old"])
    }

    /// **The cached verdict is read, not recomputed** — the whole point of
    /// storing it. An entry whose cache disagrees with its code must report the
    /// cache, or the picker is verifying on every render again.
    func testTheSignatureVerdictComesFromTheCache() {
        var stale = entry("Imported")
        stale.signatureIsValid = true  // deliberately wrong: the code is unsigned
        XCTAssertNil(TrackCode.signature(of: stale.code))
        XCTAssertTrue(stale.signatureIsValid)
    }

    // MARK: - Migration

    func testMigrationFoldsTheOldSlotIn() throws {
        let book = TrackLibraryBook.migrating(
            legacyCode: TestTracks.Code.bridgeRing, into: TrackLibraryBook(),
            now: epoch, name: "My track")

        XCTAssertEqual(book.tracks.count, 1)
        let entry = try XCTUnwrap(book.entry(id: TestTracks.Code.bridgeRing))
        XCTAssertEqual(entry.code, TestTracks.Code.bridgeRing)
        XCTAssertEqual(entry.name, "My track")
        XCTAssertFalse(entry.isImported)
    }

    /// Running it twice must not duplicate the track — the guard is "the book
    /// is empty", so a second pass over a populated book is a no-op.
    func testMigrationIsIdempotent() {
        let once = TrackLibraryBook.migrating(
            legacyCode: TestTracks.Code.bridgeRing, into: TrackLibraryBook(),
            now: epoch, name: "My track")
        let twice = TrackLibraryBook.migrating(
            legacyCode: TestTracks.Code.bridgeRing, into: once,
            now: epoch, name: "My track")

        XCTAssertEqual(twice.tracks.count, 1)
        XCTAssertEqual(twice, once)
    }

    func testMigrationWithNothingToMoveIsANoOp() {
        let empty = TrackLibraryBook()
        XCTAssertEqual(
            TrackLibraryBook.migrating(
                legacyCode: nil, into: empty, now: epoch, name: "My track"),
            empty)
        XCTAssertEqual(
            TrackLibraryBook.migrating(
                legacyCode: "", into: empty, now: epoch, name: "My track"),
            empty)
    }

    /// Every id the app can start on must resolve to a real built-in. This
    /// fails on a dangling default, which `track(id:)`'s fallback would hide.
    func testEveryBuiltinIDResolvesWithoutTheFallback() {
        for builtin in TrackLibrary.builtins {
            XCTAssertNotNil(
                TrackLibrary.builtin(id: builtin.id), "\(builtin.id) did not resolve")
        }
        XCTAssertNil(TrackLibrary.builtin(id: "practice-loop"))
    }
}
