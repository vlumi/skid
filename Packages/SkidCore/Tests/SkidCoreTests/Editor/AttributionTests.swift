import XCTest

@testable import SkidCore
@testable import SkidKit

/// What the editor says about where a pasted track came from.
@MainActor
final class AttributionTests: XCTestCase {
    private struct FixedStore: SigningKeyStore {
        let key: InMemorySigningKey
        func signer() -> TrackCode.Signer? { key }
    }

    private let mine = InMemorySigningKey()
    private let theirs = InMemorySigningKey()

    private func game() -> CouchGame {
        CouchGame(signingKeys: FixedStore(key: mine), libraryFilename: "test-\(UUID()).json")
    }

    /// `CouchGame()` reads the REAL UserDefaults, so a slot left by another test
    /// migrates into the library at init and the counts here become whatever ran
    /// first. Same hazard `TuningWireTests` documents for `@AppStorage`.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "skid.editor.customTrack")
    }

    private var layout: TrackLayout {
        // swiftlint:disable:next force_try
        try! TrackCode.decode(TestTracks.Code.bridgeRing)
    }

    func testUnsignedPastesAsUnsigned() {
        let game = game()
        XCTAssertTrue(game.loadCustomTrack(code: TrackCode.encode(layout)))
        XCTAssertEqual(game.pastedAttribution, .unsigned)
        XCTAssertFalse(game.pastedAttribution.isWorthShowing)
    }

    func testMyOwnSignatureReadsAsMine() throws {
        let game = game()
        let code = try TrackCode.encode(layout, signedBy: mine)
        XCTAssertTrue(game.loadCustomTrack(code: code))
        XCTAssertEqual(game.pastedAttribution, .mine)
    }

    func testSomeoneElsesSignatureCarriesTheirKey() throws {
        let game = game()
        let code = try TrackCode.encode(layout, signedBy: theirs)
        XCTAssertTrue(game.loadCustomTrack(code: code))
        XCTAssertEqual(game.pastedAttribution, .other(publicKey: theirs.publicKey))
    }

    /// **A bad signature does not block the track.** Attribution, not
    /// gatekeeping: the code still describes a perfectly drivable road, and
    /// refusing it would punish the recipient for the sharer's edit.
    func testABrokenSignatureStillLoadsTheTrack() throws {
        let game = game()
        let signed = try TrackCode.encode(layout, signedBy: theirs)
        var blob = try XCTUnwrap(TrackCode.base64urlDecode(signed))
        blob[8] ^= 0x01
        let tampered = TrackCode.finish(Array(blob.dropFirst(2)))

        XCTAssertTrue(game.loadCustomTrack(code: tampered), "the track must still load")
        XCTAssertEqual(game.pastedAttribution, .broken)
        XCTAssertTrue(game.pastedAttribution.isWorthShowing, "a broken signature must be visible")
    }

    /// Sharing signs by default, and `signed: false` gives the short code —
    /// the same track either way.
    func testShareCodeSignsByDefaultAndCanBeShort() throws {
        let game = game()
        game.editorLayout = layout
        let signed = try XCTUnwrap(game.shareCode())
        let short = try XCTUnwrap(game.shareCode(signed: false))

        XCTAssertEqual(TrackCode.signature(of: signed)?.isValid, true)
        XCTAssertNil(TrackCode.signature(of: short))
        XCTAssertGreaterThan(signed.count, short.count + 100)
        XCTAssertEqual(try TrackCode.decode(signed), try TrackCode.decode(short))
    }

    /// The id the app boots on must be a real built-in. It was
    /// `"practice-loop"`, which does not exist — masked by `track(id:)`'s
    /// silent fallback, so the lobby read hiscores for a nonexistent track.
    func testTheDefaultTrackIDResolves() {
        XCTAssertNotNil(TrackLibrary.builtin(id: CouchGame(signingKeys: NoSigningKey()).trackID))
    }

    /// With no key available, sharing still works — unsigned.
    func testSharingWithoutAKeyFallsBackToUnsigned() throws {
        let game = CouchGame(signingKeys: NoSigningKey())
        game.editorLayout = layout
        let code = try XCTUnwrap(game.shareCode())
        XCTAssertNil(TrackCode.signature(of: code))
        XCTAssertEqual(try TrackCode.decode(code), layout)
    }
}
