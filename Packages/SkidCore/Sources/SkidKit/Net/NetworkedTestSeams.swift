import Foundation
import SkidCore

/// **Driving two `NetworkedGame`s against each other in one process.**
///
/// The device failures that cost the most were all in the send/receive loop, and
/// nothing could exercise it without a radio — so sends are captured into an
/// outbox the test hands to the other side, with whatever latency and loss it
/// wants to impose. Instant delivery is not a simplified network; it is a
/// different thing that cannot fail the way one does.
@MainActor
extension NetworkedGame {
    /// Start a race without a lobby handshake.
    func adoptForTesting(_ message: RaceStart) {
        captureSends = true
        apply(message)
    }

    /// Whether this device is advertising — the phase claiming `.hosting` is not
    /// the same thing as the radio being on.
    var isAdvertisingForTesting: Bool { transport.isAdvertising }

    /// Capture sends without adopting a race — so the LOBBY handshake can be
    /// driven in one process too, which is where the session loop lives.
    func captureSendsForTesting() {
        captureSends = true
    }

    /// Take everything queued since the last call.
    func drainOutbox() -> [[UInt8]] {
        defer { outbox.removeAll() }
        return outbox
    }

    /// Feed in what a peer sent.
    func deliverForTesting(_ bytes: [UInt8], from peer: RaceRoster.PeerName) {
        transport(didReceive: bytes, from: peer)
    }
}
