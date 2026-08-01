import CryptoKit
import Foundation

/// **Where a signing key comes from.** The store is the seam: SkidKit backs it
/// with the Keychain, tests back it with memory.
///
/// A store that cannot produce a key returns nil rather than throwing, and the
/// caller shares an unsigned code. That path is not an edge case — `swift test`
/// runs headless with no entitlements, where Keychain access fails outright, so
/// it is exercised constantly and must be the boring one.
public protocol SigningKeyStore {
    /// The device's signing key, creating one on first use. Nil when the store
    /// is unavailable.
    func signer() -> TrackCode.Signer?
}

/// An Ed25519 key held in memory. The real store's counterpart for tests, and
/// the thing a Keychain-backed store wraps once it has raw key bytes.
public struct InMemorySigningKey: TrackCode.Signer, Sendable {
    private let key: Curve25519.Signing.PrivateKey

    public init() {
        key = Curve25519.Signing.PrivateKey()
    }

    /// Restore from stored bytes; nil if they are not a valid key.
    public init?(rawRepresentation: [UInt8]) {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: rawRepresentation)
        else { return nil }
        self.key = key
    }

    /// The private key's bytes, for a store to persist.
    public var rawRepresentation: [UInt8] { Array(key.rawRepresentation) }

    public var publicKey: [UInt8] { Array(key.publicKey.rawRepresentation) }

    public func sign(_ bytes: [UInt8]) throws -> [UInt8] {
        Array(try key.signature(for: Data(bytes)))
    }
}

/// A store with no key at all — what an unavailable Keychain looks like, so the
/// unsigned fallback can be tested directly.
public struct NoSigningKey: SigningKeyStore {
    public init() {}
    public func signer() -> TrackCode.Signer? { nil }
}
