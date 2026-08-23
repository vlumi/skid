import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Taking a track in from a link, a code, or a scan.**
///
/// Importing is collecting, not editing: it adds a row and leaves whatever is on
/// the canvas alone — a player who taps Add expects a new track, not to lose
/// their unsaved one.
@MainActor
final class TrackImportTests: XCTestCase {
    /// **The legacy slot is process-wide state**, so a code left in
    /// `UserDefaults` by another suite migrates into every library built here as
    /// a "My track" nobody imported. Cleared per test, as the other editor
    /// suites do — the same trap the tuning dials and the setup memory document.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "skid.editor.customTrack")
    }

    private func game() -> CouchGame {
        CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "import-\(UUID().uuidString).json",
            profileFilename: "import-\(UUID().uuidString).json",
            setupFilename: "import-\(UUID().uuidString).json")
    }

    private var code: String { TrackLibrary.builtins[0].code }

    func testABareCodeIsImported() {
        let couch = game()
        let outcome = couch.importTrack(fromPasted: code)
        guard case .added = outcome else { return XCTFail("not added: \(outcome)") }
        XCTAssertEqual(couch.library.tracks.count, 1)
        XCTAssertTrue(couch.library.tracks[0].isRaceable)
    }

    /// **A link's name is the sender's name for it**, which beats "Imported
    /// track" — that is the whole reason the name rides in the URL.
    func testALinkBringsItsName() throws {
        let couch = game()
        let url = try XCTUnwrap(TrackLink.url(code: code, name: "Hairpin Alley"))
        let outcome = couch.importTrack(fromPasted: url.absoluteString)
        XCTAssertEqual(outcome, .added(name: "Hairpin Alley"))
        XCTAssertEqual(couch.library.tracks.first?.name, "Hairpin Alley")
    }

    /// A link with no name still imports, under a placeholder that can be
    /// renamed like anything else in the library.
    func testALinkWithoutANameStillImports() throws {
        let couch = game()
        let url = try XCTUnwrap(TrackLink.url(code: code))
        guard case .added(let name) = couch.importTrack(fromPasted: url.absoluteString) else {
            return XCTFail("a nameless link did not import")
        }
        XCTAssertFalse(name.isEmpty)
    }

    /// **The same road twice is one row.** Identity is the content, so a track
    /// that arrives as a link and then as a scan does not pile up near-duplicates
    /// the player has to tell apart.
    func testImportingTheSameTrackTwiceIsNotADuplicate() throws {
        let couch = game()
        let url = try XCTUnwrap(TrackLink.url(code: code, name: "Mine"))
        _ = couch.importTrack(fromPasted: url.absoluteString)
        let second = couch.importTrack(fromPasted: code)  // same road, bare this time
        XCTAssertEqual(second, .alreadyHave(name: "Mine"))
        XCTAssertEqual(couch.library.tracks.count, 1, "the same track was filed twice")
    }

    func testUnreadableTextIsReportedRatherThanIgnored() {
        let couch = game()
        XCTAssertEqual(couch.importTrack(fromPasted: "hello"), .unreadable)
        XCTAssertEqual(couch.importTrack(fromPasted: ""), .unreadable)
        XCTAssertEqual(
            couch.importTrack(fromPasted: "https://skid.misaki.fi/t/not-a-code"), .unreadable)
        XCTAssertTrue(couch.library.tracks.isEmpty)
    }

    /// **Importing must not touch the canvas.** The editor's paste replaces what
    /// you are working on; this one does not, and a player who loses an unsaved
    /// track to an Add button would not forgive it.
    func testImportingLeavesTheEditorAlone() throws {
        let couch = game()
        couch.newTrackForEditing()
        let before = try XCTUnwrap(couch.editorLayout)
        _ = couch.importTrack(fromPasted: code)
        XCTAssertEqual(couch.editorLayout, before, "the import changed the canvas")
        XCTAssertEqual(couch.library.tracks.count, 1)
    }

    /// The library survives a relaunch with the imported track in it — an import
    /// that vanishes is worse than one that fails.
    func testAnImportedTrackPersists() throws {
        let filename = "import-persist-\(UUID().uuidString).json"
        let before = CouchGame(signingKeys: NoSigningKey(), libraryFilename: filename)
        let url = try XCTUnwrap(TrackLink.url(code: code, name: "Kept"))
        _ = before.importTrack(fromPasted: url.absoluteString)

        let after = CouchGame(signingKeys: NoSigningKey(), libraryFilename: filename)
        XCTAssertEqual(after.library.tracks.map(\.name), ["Kept"])
    }
}
