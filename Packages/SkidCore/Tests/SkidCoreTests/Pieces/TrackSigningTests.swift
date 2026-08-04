import CryptoKit
import XCTest

@testable import SkidCore

/// **Attribution on a share code.** A signature proves the holder of one key
/// signed these exact bytes — not that the track is unmodified by anyone since,
/// and not that the key belongs to any particular person.
final class TrackSigningTests: XCTestCase {
    /// An in-memory key. The Keychain-backed signer is SkidKit's problem;
    /// `swift test` runs headless with no entitlements, so it could not be used
    /// here even if it existed.
    private struct TestSigner: TrackCode.Signer {
        let key: Curve25519.Signing.PrivateKey
        var publicKey: [UInt8] { Array(key.publicKey.rawRepresentation) }
        func sign(_ bytes: [UInt8]) throws -> [UInt8] {
            Array(try key.signature(for: Data(bytes)))
        }
    }

    private let signer = TestSigner(key: Curve25519.Signing.PrivateKey())
    private var layout: TrackLayout {
        // swiftlint:disable:next force_try
        try! TrackCode.decode(TestTracks.Code.bridgeRing)
    }

    func testASignedCodeReportsItsKeyAndVerifies() throws {
        let code = try TrackCode.encode(layout, signedBy: signer)
        let signature = try XCTUnwrap(TrackCode.signature(of: code))
        XCTAssertEqual(signature.publicKey, signer.publicKey)
        XCTAssertTrue(signature.isValid)
    }

    /// A signed code still decodes to the same track — the extra sections are
    /// skipped by the layout decoder.
    func testSigningDoesNotChangeTheTrack() throws {
        let code = try TrackCode.encode(layout, signedBy: signer)
        XCTAssertEqual(try TrackCode.decode(code), layout)
    }

    /// Stripping a signature is well defined: the unsigned prefix is exactly
    /// what `encode` alone produces.
    func testTheUnsignedPrefixIsThePlainCode() throws {
        let signed = try TrackCode.encode(layout, signedBy: signer)
        let plain = TrackCode.encode(layout)
        let body = try XCTUnwrap(TrackCode.base64urlDecode(signed)).dropFirst(2)
        let plainBody = try XCTUnwrap(TrackCode.base64urlDecode(plain)).dropFirst(2)
        XCTAssertEqual(Array(body.prefix(plainBody.count)), Array(plainBody))
    }

    func testAnUnsignedCodeHasNoSignature() {
        XCTAssertNil(TrackCode.signature(of: TrackCode.encode(layout)))
        XCTAssertNil(TrackCode.signature(of: TestTracks.Code.clover))
    }

    /// Tampering the CONTENT with a repaired CRC — so only the signature can
    /// catch it. Without the CRC repair this would test the CRC, not the
    /// signature.
    func testEditedContentFailsVerification() throws {
        let code = try TrackCode.encode(layout, signedBy: signer)
        var blob = try XCTUnwrap(TrackCode.base64urlDecode(code))
        blob[8] ^= 0x01  // somewhere inside the pieces payload
        let tampered = reframed(blob)
        XCTAssertEqual(TrackCode.signature(of: tampered)?.isValid, false)
    }

    /// **The pubkey is inside the signed range.** Swapping it for another key
    /// must not produce a code that verifies as that other author — otherwise
    /// anyone could re-attribute a signed track without the private key.
    func testSwappingThePublicKeyFailsVerification() throws {
        let code = try TrackCode.encode(layout, signedBy: signer)
        var blob = try XCTUnwrap(TrackCode.base64urlDecode(code))
        let other = Array(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        let at = try XCTUnwrap(indexOfPayload(tag: 254, in: blob))
        blob.replaceSubrange(at..<(at + 32), with: other)
        XCTAssertEqual(TrackCode.signature(of: reframed(blob))?.isValid, false)
    }

    /// **Verification runs on the received bytes, not a re-encode.** Sections
    /// carry their own tags, so a reordered body decodes to the same layout and
    /// re-encodes canonically — verifying that way would attest to bytes nobody
    /// signed. This is the test that pins the whole discipline.
    func testAReorderedBodyFailsVerification() throws {
        let code = try TrackCode.encode(layout, signedBy: signer)
        let blob = try XCTUnwrap(TrackCode.base64urlDecode(code))
        let records = splitRecords(Array(blob.dropFirst(2)))
        XCTAssertGreaterThan(records.count, 3)
        // Swap the first two content records; SIG stays last.
        var reordered = records
        reordered.swapAt(0, 1)
        let body = reordered.flatMap { $0 }
        let rebuilt = TrackCode.finish(body)

        // It still decodes to the same track — which is exactly the hazard.
        XCTAssertEqual(try TrackCode.decode(rebuilt), layout)
        XCTAssertEqual(TrackCode.signature(of: rebuilt)?.isValid, false)
    }

    /// A SIG record that isn't last is not a signature.
    ///
    /// Both trailers are 64 bytes on purpose. A short one is refused by the
    /// length check whether or not the tag is examined, so it cannot tell the
    /// two rules apart — only a trailer the right size proves the LAST RECORD
    /// MUST BE TAGGED `sig`, rather than merely being the right length.
    func testASignatureMustBeTheLastRecord() throws {
        let code = try TrackCode.encode(layout, signedBy: signer)
        let signed = Array(try XCTUnwrap(TrackCode.base64urlDecode(code)).dropFirst(2))

        var unknownTrailer = signed
        TrackCode.appendSection(&unknownTrailer, .decals, Array(repeating: 0, count: 64))
        XCTAssertNil(TrackCode.signature(of: TrackCode.finish(unknownTrailer)))

        // And a second SIG after the first: the earlier one no longer covers
        // the body, so this must not verify against it.
        var doubled = signed
        TrackCode.appendSection(&doubled, .sig, Array(repeating: 0, count: 64))
        XCTAssertEqual(TrackCode.signature(of: TrackCode.finish(doubled))?.isValid, false)
    }

    /// Malformed envelopes are refused rather than crashing or half-verifying.
    func testMalformedSignatureSectionsAreRefused() throws {
        let plain = TrackCode.encodedBody(layout)

        var shortSig = plain
        TrackCode.appendSection(&shortSig, .pubkey, signer.publicKey)
        TrackCode.appendSection(&shortSig, .sig, Array(repeating: 0, count: 63))
        XCTAssertNil(TrackCode.signature(of: TrackCode.finish(shortSig)))

        var noKey = plain
        TrackCode.appendSection(&noKey, .sig, Array(repeating: 0, count: 64))
        XCTAssertNil(TrackCode.signature(of: TrackCode.finish(noKey)))

        var shortKey = plain
        TrackCode.appendSection(&shortKey, .pubkey, Array(repeating: 0, count: 31))
        TrackCode.appendSection(&shortKey, .sig, Array(repeating: 0, count: 64))
        XCTAssertNil(TrackCode.signature(of: TrackCode.finish(shortKey)))

        // CryptoKit accepts any 32 bytes as a key — validity is decided at
        // verification, not construction. So a garbage key is reported as a
        // signature that does not check out, rather than as no signature: the
        // code does claim one. It must not crash, which is the point here.
        var badPoint = plain
        TrackCode.appendSection(&badPoint, .pubkey, Array(repeating: 0xFF, count: 32))
        TrackCode.appendSection(&badPoint, .sig, Array(repeating: 0, count: 64))
        XCTAssertEqual(TrackCode.signature(of: TrackCode.finish(badPoint))?.isValid, false)

        var keyOnly = plain
        TrackCode.appendSection(&keyOnly, .pubkey, signer.publicKey)
        XCTAssertNil(TrackCode.signature(of: TrackCode.finish(keyOnly)))
    }

    /// Signing twice must both verify — deliberately NOT that the bytes match.
    /// Ed25519 is deterministic per RFC 8032, but CryptoKit does not promise it,
    /// and pinning signature bytes would be a time bomb.
    func testSigningTwiceBothVerify() throws {
        let first = try TrackCode.encode(layout, signedBy: signer)
        let second = try TrackCode.encode(layout, signedBy: signer)
        XCTAssertEqual(TrackCode.signature(of: first)?.isValid, true)
        XCTAssertEqual(TrackCode.signature(of: second)?.isValid, true)
    }

    /// The measured cost, so the QR budget stays honest as sections are added.
    func testASignedCodeStaysInsideTheQRBudget() throws {
        let code = try TrackCode.encode(layout, signedBy: signer)
        // The stable invariant is BYTES: PUBKEY (2 + 32) plus SIG (2 + 64) = 100.
        // Character overhead is not stable — base64url packs 3 bytes into 4 chars,
        // so the same 100 bytes cost 133 or 134 characters depending on the
        // payload's length mod 3. Pinning 133 held only for the payload of the day
        // and broke the moment the fixture gained a section.
        let signedBytes = try XCTUnwrap(TrackCode.base64urlDecode(code)).count
        let plainBytes = try XCTUnwrap(
            TrackCode.base64urlDecode(TrackCode.encode(layout))
        ).count
        XCTAssertEqual(signedBytes - plainBytes, 100)
        XCTAssertLessThan("https://skid.misaki.fi/t/".count + code.count, 250)
    }

    // MARK: - Helpers

    private typealias Tag = TrackCode.Tag

    /// Re-frame a tampered blob so its CRC matches again — the point being to
    /// test the signature rather than the CRC.
    private func reframed(_ blob: [UInt8]) -> String {
        TrackCode.finish(Array(blob.dropFirst(2)))
    }

    private func splitRecords(_ body: [UInt8]) -> [[UInt8]] {
        var records: [[UInt8]] = []
        var index = 0
        while index + 2 <= body.count {
            let length = Int(body[index + 1])
            let end = index + 2 + length
            guard end <= body.count else { break }
            records.append(Array(body[index..<end]))
            index = end
        }
        return records
    }

    /// Where a tag's payload starts in the whole blob (header included).
    private func indexOfPayload(tag: UInt8, in blob: [UInt8]) -> Int? {
        var index = 2
        while index + 2 <= blob.count {
            let length = Int(blob[index + 1])
            if blob[index] == tag { return index + 2 }
            index += 2 + length
        }
        return nil
    }
}
