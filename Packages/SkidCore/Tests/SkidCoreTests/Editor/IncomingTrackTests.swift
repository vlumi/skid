import XCTest

@testable import SkidCore
@testable import SkidKit

/// **A track arriving from outside** — a tapped link today, a scanned code next.
///
/// Offered, never filed silently: the app is being handed something by a third
/// party, and one that writes to your library on a tap is one you stop trusting.
@MainActor
final class IncomingTrackTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // The legacy slot is process-wide; see `TrackImportTests`.
        UserDefaults.standard.removeObject(forKey: "skid.editor.customTrack")
    }

    private func game() -> CouchGame {
        CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "incoming-\(UUID().uuidString).json",
            profileFilename: "incoming-\(UUID().uuidString).json",
            setupFilename: "incoming-\(UUID().uuidString).json")
    }

    private var code: String { TrackLibrary.builtins[0].code }

    private func link(name: String? = nil) throws -> URL {
        try XCTUnwrap(TrackLink.url(code: code, name: name))
    }

    /// **A link offers; it does not file.** Nothing reaches the library until
    /// somebody says yes.
    func testATappedLinkOffersRatherThanImporting() throws {
        let couch = game()
        XCTAssertTrue(couch.receive(url: try link(name: "Gift")))
        XCTAssertEqual(couch.incomingTrack?.name, "Gift")
        XCTAssertTrue(couch.library.tracks.isEmpty, "the link filed a track without asking")
        // And it lands on the library, where the answer belongs — not into
        // whatever screen happened to be open.
        XCTAssertEqual(couch.phase, .tracks)
    }

    func testAcceptingFilesIt() throws {
        let couch = game()
        _ = couch.receive(url: try link(name: "Gift"))
        XCTAssertEqual(couch.acceptIncomingTrack(), .added(name: "Gift"))
        XCTAssertEqual(couch.library.tracks.map(\.name), ["Gift"])
        XCTAssertNil(couch.incomingTrack, "the offer stayed pending after accepting")
    }

    /// **Declining writes nothing** — the point of asking.
    func testDecliningWritesNothing() throws {
        let couch = game()
        _ = couch.receive(url: try link())
        couch.declineIncomingTrack()
        XCTAssertNil(couch.incomingTrack)
        XCTAssertTrue(couch.library.tracks.isEmpty)
    }

    /// The sheet's dismiss calls decline, and accepting dismisses — so decline
    /// runs after accept. That must not undo the import or crash.
    func testDecliningAfterAcceptingIsHarmless() throws {
        let couch = game()
        _ = couch.receive(url: try link(name: "Gift"))
        _ = couch.acceptIncomingTrack()
        couch.declineIncomingTrack()  // what the sheet's dismiss binding does
        XCTAssertEqual(couch.library.tracks.map(\.name), ["Gift"], "the accepted track vanished")
    }

    /// A link for a track already held says so, so nobody is offered a copy the
    /// library cannot hold (identity is the content).
    func testALinkForATrackYouHaveSaysSo() throws {
        let couch = game()
        _ = couch.importTrack(fromPasted: code)
        _ = couch.receive(url: try link(name: "Gift"))
        XCTAssertEqual(couch.incomingTrack?.alreadyHave, true)
        // Accepting anyway cannot produce a second row.
        _ = couch.acceptIncomingTrack()
        XCTAssertEqual(couch.library.tracks.count, 1)
    }

    /// A URL that is not a track link is ignored — a mis-tapped link should say
    /// nothing rather than pop an error nobody caused.
    func testANonTrackURLIsIgnored() throws {
        let couch = game()
        XCTAssertFalse(couch.receive(url: try XCTUnwrap(URL(string: "https://skid.misaki.fi/"))))
        XCTAssertFalse(
            couch.receive(url: try XCTUnwrap(URL(string: "https://example.com/hello"))))
        XCTAssertNil(couch.incomingTrack)
    }

    /// **Both link forms arrive**, since either may have been shared.
    func testTheFragmentFormArrivesToo() throws {
        let couch = game()
        let url = try XCTUnwrap(URL(string: "https://skid.misaki.fi/t/#\(code)"))
        XCTAssertTrue(couch.receive(url: url))
        XCTAssertEqual(couch.incomingTrack?.code, code)
    }
}
