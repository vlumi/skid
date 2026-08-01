import Foundation

/// **What a code says about where it came from**, as one value the UI can show.
///
/// A tri-state, not two booleans: "unsigned" and "signed but doesn't check out"
/// are different facts, and collapsing them would throw away the only signal
/// that something was edited after signing.
public enum TrackAttribution: Equatable, Sendable {
    /// No signature. The normal case for a track you built, and for every
    /// built-in — nothing is wrong.
    case unsigned
    /// Signed by the key this device holds.
    case mine
    /// Signed by someone else. The key identifies them; a display name is a
    /// later concern (profiles, v0.9).
    case other(publicKey: [UInt8])
    /// Carries a signature that does not verify — edited after signing, or
    /// tampered with. **Still a loadable track**: this is attribution, not
    /// gatekeeping.
    case broken

    /// Read a code's attribution, given the key this device signs with (nil if
    /// it has none yet).
    public static func of(_ code: String, myPublicKey: [UInt8]?) -> TrackAttribution {
        guard let signature = TrackCode.signature(of: code) else { return .unsigned }
        guard signature.isValid else { return .broken }
        return signature.publicKey == myPublicKey ? .mine : .other(publicKey: signature.publicKey)
    }

    /// Whether this is worth showing at all. An unsigned track is the norm, so
    /// saying so would be noise on every built-in.
    public var isWorthShowing: Bool { self != .unsigned }
}
