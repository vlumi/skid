import CryptoKit
import Foundation

/// **Signing a share code**: attribution, so a track that travels can say who
/// made it.
///
/// Not integrity against a malicious sharer — anyone can strip a signature and
/// re-sign as themselves, because nothing vouches for which key is whom. What
/// it proves is that the holder of one key signed these exact bytes, and that
/// two tracks signed by the same key came from the same person.
///
/// CryptoKit rather than a hand-rolled curve: it is an Apple framework, not a
/// third-party dependency, and Ed25519 verification is a pure function of bytes
/// — more deterministic than the `Double` math already in the sim. Key
/// generation and storage are I/O and live in SkidKit; only the pure half is
/// here, where the coverage gate can see it.
extension TrackCode {
    /// What a code says about its author.
    public struct Signature: Equatable, Sendable {
        /// The 32-byte Ed25519 public key that signed it.
        public var publicKey: [UInt8]
        /// Whether the signature actually checks out against those bytes. False
        /// means the track was edited after signing, or the signature was
        /// tampered with — a display fact, not a reason to refuse the track.
        public var isValid: Bool
    }

    /// Something that can sign, without saying where the key lives. The
    /// Keychain-backed implementation is in SkidKit; tests use an in-memory key.
    public protocol Signer {
        /// The 32-byte raw public key.
        var publicKey: [UInt8] { get }
        /// A 64-byte Ed25519 signature over `bytes`.
        func sign(_ bytes: [UInt8]) throws -> [UInt8]
    }

    public static let publicKeyLength = 32
    public static let signatureLength = 64

    /// **Encode and sign** — a separate entry point from `encode`, deliberately.
    ///
    /// `encode` runs on every edit for the undo snapshot, so signing must not be
    /// on that path: it would cost an Ed25519 operation per keystroke and grow
    /// every snapshot by ~135 chars. Do not "helpfully" unify the two.
    ///
    /// The unsigned prefix of the result is byte-identical to `encode(layout)`,
    /// so stripping a signature is well defined.
    public static func encode(_ layout: TrackLayout, signedBy signer: Signer) throws -> String {
        var body = encodedBody(layout)
        appendSection(&body, .pubkey, signer.publicKey)
        // PUBKEY is inside the signed range: outside it, anyone could swap the
        // key for their own and the signature would still verify against it.
        appendSection(&body, .sig, try signer.sign(body))
        return finish(body)
    }

    /// What a code claims about its author, or nil when it carries no signature.
    ///
    /// Works on the **received bytes**, and never decodes the layout first:
    /// `parseSections` discards section order, so a reordered blob re-encodes
    /// canonically and would wrongly verify. Signature-checking and
    /// layout-decoding are independent passes over the same string.
    public static func signature(of code: String) -> Signature? {
        guard code.count <= maxCodeLength, let blob = base64urlDecode(code),
            blob.count >= 2
        else { return nil }
        let body = Array(blob[2...])
        guard let sig = trailingSignature(in: body) else { return nil }
        guard let key = sectionPayload(.pubkey, in: sig.signed),
            key.count == publicKeyLength,
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key)
        else { return nil }
        let valid = publicKey.isValidSignature(Data(sig.signature), for: Data(sig.signed))
        return Signature(publicKey: key, isValid: valid)
    }

    /// The SIG record and the bytes it covers — everything before it.
    ///
    /// Located **by tag**, walking the records, rather than by slicing a fixed
    /// count off the end: nothing in a TLV format is positional, and hardcoding
    /// the length would freeze Ed25519's 64 bytes into the format. A SIG record
    /// anywhere but last is rejected, so a code whose tail merely resembles one
    /// cannot be checked against a garbage prefix.
    private static func trailingSignature(
        in body: [UInt8]
    ) -> (signed: [UInt8], signature: [UInt8])? {
        var index = 0
        var lastRecord: (start: Int, payload: [UInt8])?
        var lastTag: Tag?
        while index < body.count {
            guard index + 2 <= body.count else { return nil }
            let length = Int(body[index + 1])
            let start = index + 2
            guard start + length <= body.count else { return nil }
            lastTag = Tag(rawValue: body[index])
            lastRecord = (index, Array(body[start..<start + length]))
            index = start + length
        }
        guard lastTag == .sig, let last = lastRecord,
            last.payload.count == signatureLength
        else { return nil }
        return (Array(body[0..<last.start]), last.payload)
    }

    /// One section's payload, by tag, from a raw body.
    private static func sectionPayload(_ wanted: Tag, in body: [UInt8]) -> [UInt8]? {
        var index = 0
        while index < body.count {
            guard index + 2 <= body.count else { return nil }
            let length = Int(body[index + 1])
            let start = index + 2
            guard start + length <= body.count else { return nil }
            if Tag(rawValue: body[index]) == wanted {
                return Array(body[start..<start + length])
            }
            index = start + length
        }
        return nil
    }
}
