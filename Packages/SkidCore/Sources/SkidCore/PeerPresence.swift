import Foundation

/// **Who is still here — with a grace period, because a hiccup is not a
/// departure.**
///
/// MultipeerConnectivity reports a peer lost on short interruptions: a phone
/// glancing at another radio, a moment behind a body, a burst the link never
/// recovers in time. Treating every one of those as a departure ejects players
/// mid-race for nothing, which is a worse failure than a car that coasts for a
/// second.
///
/// So a loss is **provisional** until the link stays down. Before the deadline
/// the car holds its last input and the screen says the player is fading; after
/// it, they are out — and out for good, because there is no mid-race rejoin (a
/// deliberate call: with a host authority a late client could adopt a snapshot
/// and start rendering, but after a few seconds away, rejoining a short race is
/// meaningless).
///
/// Pure timing, no transport: it is fed elapsed seconds, so the whole thing is
/// testable without a radio.
public struct PeerPresence: Equatable, Sendable {
    /// How long a peer may be gone before it counts as gone for good.
    ///
    /// Three seconds: long enough to cover the interruptions MC reports
    /// spuriously, short enough that nobody watches a ghost car for a whole
    /// corner. A short race is ~30 s, so this is a tenth of it — the ceiling on
    /// what is worth waiting for.
    public static let grace: TimeInterval = 3

    /// Peers whose link is down, and for how long.
    private var fading: [RaceRoster.PeerName: TimeInterval] = [:]
    /// Peers whose grace expired. Sticky: there is no way back into this race.
    private var departed: Set<RaceRoster.PeerName> = []

    public init() {}

    /// The transport lost a peer. Provisional until `grace` elapses.
    ///
    /// A peer already departed stays departed — a flapping link must not
    /// resurrect somebody the race has already written off, or their car would
    /// rejoin mid-corner from a stale position.
    public mutating func lost(_ peer: RaceRoster.PeerName) {
        guard !departed.contains(peer) else { return }
        fading[peer] = 0
    }

    /// The transport got the peer back inside the grace period.
    @discardableResult
    public mutating func recovered(_ peer: RaceRoster.PeerName) -> Bool {
        guard !departed.contains(peer) else { return false }
        return fading.removeValue(forKey: peer) != nil
    }

    /// Advance time. Returns the peers whose grace just expired — each reported
    /// exactly once, so a caller can act on the transition rather than poll.
    public mutating func advance(by dt: TimeInterval) -> [RaceRoster.PeerName] {
        var expired: [RaceRoster.PeerName] = []
        for (peer, elapsed) in fading {
            let total = elapsed + dt
            if total >= Self.grace {
                fading.removeValue(forKey: peer)
                departed.insert(peer)
                expired.append(peer)
            } else {
                fading[peer] = total
            }
        }
        return expired.sorted()
    }

    /// Gone, and not coming back to this race.
    public func hasDeparted(_ peer: RaceRoster.PeerName) -> Bool {
        departed.contains(peer)
    }

    /// Link down but still inside the grace period — what "fading" chrome shows.
    public func isFading(_ peer: RaceRoster.PeerName) -> Bool {
        fading[peer] != nil
    }

    public var fadingPeers: [RaceRoster.PeerName] { fading.keys.sorted() }
    public var departedPeers: [RaceRoster.PeerName] { departed.sorted() }

    /// Everyone who is neither fading nor gone, out of a roster's peers.
    public func present(in roster: RaceRoster) -> [RaceRoster.PeerName] {
        roster.peers.filter { fading[$0] == nil && !departed.contains($0) }
    }

    /// Forget everything — a fresh race, where last race's departures are not
    /// this race's problem.
    public mutating func reset() {
        fading.removeAll()
        departed.removeAll()
    }
}
