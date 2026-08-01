import XCTest

@testable import SkidCore

/// The seam between "who signs" and "where the key lives". The Keychain-backed
/// store is SkidKit's and cannot run here — `swift test` is headless with no
/// entitlements — which is exactly why the seam exists.
final class SigningKeyStoreTests: XCTestCase {
    private struct FixedStore: SigningKeyStore {
        let key: InMemorySigningKey
        func signer() -> TrackCode.Signer? { key }
    }

    private var layout: TrackLayout {
        // swiftlint:disable:next force_try
        try! TrackCode.decode(TestTracks.Code.bridgeRing)
    }

    /// A store with a key signs; the code verifies against that key.
    func testAStoreWithAKeySigns() throws {
        let store = FixedStore(key: InMemorySigningKey())
        let signer = try XCTUnwrap(store.signer())
        let code = try TrackCode.encode(layout, signedBy: signer)
        let signature = try XCTUnwrap(TrackCode.signature(of: code))
        XCTAssertTrue(signature.isValid)
        XCTAssertEqual(signature.publicKey, signer.publicKey)
    }

    /// **No key is a working outcome, not an error.** An unavailable Keychain
    /// must leave the player with a plain shareable code, not a failure.
    func testNoKeyFallsBackToAnUnsignedCode() throws {
        let store = NoSigningKey()
        XCTAssertNil(store.signer())

        let code = try shareCode(of: layout, using: store)
        XCTAssertEqual(code, TrackCode.encode(layout))
        XCTAssertNil(TrackCode.signature(of: code))
        XCTAssertEqual(try TrackCode.decode(code), layout)
    }

    /// The same store keeps the same identity across signatures — a key that
    /// changed per call would make attribution meaningless.
    func testTheKeyIsStableAcrossCalls() throws {
        let store = FixedStore(key: InMemorySigningKey())
        let first = try XCTUnwrap(store.signer()).publicKey
        let second = try XCTUnwrap(store.signer()).publicKey
        XCTAssertEqual(first, second)
    }

    /// A stored key round-trips through its raw bytes — what the Keychain
    /// actually persists.
    func testAKeyRestoresFromItsRawBytes() throws {
        let original = InMemorySigningKey()
        let restored = try XCTUnwrap(
            InMemorySigningKey(rawRepresentation: original.rawRepresentation))
        XCTAssertEqual(restored.publicKey, original.publicKey)

        let code = try TrackCode.encode(layout, signedBy: restored)
        XCTAssertEqual(TrackCode.signature(of: code)?.isValid, true)
    }

    func testGarbageBytesAreNotAKey() {
        XCTAssertNil(InMemorySigningKey(rawRepresentation: [1, 2, 3]))
    }

    /// Share a track, signing it when a key is available. The shape PR 5's UI
    /// will call; pinned here so the fallback is covered before it has a button.
    private func shareCode(of layout: TrackLayout, using store: SigningKeyStore) throws -> String {
        guard let signer = store.signer() else { return TrackCode.encode(layout) }
        return try TrackCode.encode(layout, signedBy: signer)
    }
}
