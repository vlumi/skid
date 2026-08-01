import Foundation
import Security
import SkidCore

/// The device's signing key, in the Keychain and synced through iCloud so the
/// same author identity follows the user across their devices.
///
/// **Lazy**: the key is created on first signature, not at launch. Someone who
/// never shares a track never gets one.
///
/// **Never throws.** Every failure — no entitlement, locked device, a headless
/// test process — returns nil, and the caller shares an unsigned code instead.
/// That is a working outcome, not an error to report: signing is attribution,
/// and a track without it is still a perfectly good track.
public struct KeychainSigningKeyStore: SigningKeyStore {
    private let account = "fi.misaki.skid.signing-key"

    public init() {}

    public func signer() -> TrackCode.Signer? {
        if let existing = load() { return existing }
        let fresh = InMemorySigningKey()
        // A key that cannot be saved is not used: signing with a different key
        // every launch would make attribution meaningless.
        guard save(fresh) else { return nil }
        return fresh
    }

    private func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "fi.misaki.skid",
            kSecAttrAccount as String: account,
            // Follows the user's iCloud Keychain, so one identity spans their
            // devices. Synchronizable items cannot be `…ThisDeviceOnly`, which
            // is why the accessibility below is the plain after-first-unlock.
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
    }

    private func load() -> InMemorySigningKey? {
        var request = query()
        request[kSecReturnData as String] = kCFBooleanTrue as Any
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return InMemorySigningKey(rawRepresentation: Array(data))
    }

    private func save(_ key: InMemorySigningKey) -> Bool {
        var request = query()
        request[kSecValueData as String] = Data(key.rawRepresentation)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(request as CFDictionary, nil) == errSecSuccess
    }
}
