import Foundation

/// **Do the peers still agree?** — the spike's core measurement, and the reason
/// `Race.stateHash` exists.
///
/// Each peer simulates every car and announces the hash of the state it reached.
/// If two peers ever report different hashes for the same tick, inputs-only sync
/// has failed and every frame after it is fiction. Catching that at the tick it
/// happens is the difference between "networked racing doesn't work" and a
/// diagnosis.
///
/// **A divergence is the point of the spike, not a setback.** The float-determinism
/// assumption (IEEE-754 does not pin `sin`/`cos`/`atan2`/`pow`) is exactly what
/// this is built to test on real hardware, so it is designed to *report* clearly
/// rather than to paper over.
///
/// Comparison is deliberately cheap and late: hashes are traded unreliably and
/// out of band, never gating a tick. A peer that has not reported yet is simply
/// unknown — waiting on agreement would turn a diagnostic into a second thing
/// that can stall the race.
public struct DivergenceWatch: Sendable {
    /// Hashes this peer computed, by tick, awaiting a comparison.
    private var mine: [Tick: UInt64] = [:]
    /// What each other peer reported, by tick.
    private var theirs: [PeerName: [Tick: UInt64]] = [:]

    /// Whatever the transport calls a peer. A `String` on purpose: the watch has
    /// no opinion about MultipeerConnectivity's `MCPeerID` or a UDP endpoint, and
    /// naming one here would tie the diagnostic to the transport it is meant to
    /// outlive.
    public typealias PeerName = String

    /// The first disagreement seen, if any. Sticky: once peers diverge they stay
    /// diverged, and later ticks are meaningless rather than informative.
    public private(set) var firstDivergence: Divergence?

    /// How many ticks of hashes to keep. At 60 Hz this is two seconds — long
    /// enough for a peer's report to arrive late, short enough that a long race
    /// does not accumulate a hash per tick forever.
    public static let window = 120

    public struct Divergence: Equatable, Sendable {
        public let tick: Tick
        public let peer: PeerName
        public let mine: UInt64
        public let theirs: UInt64
    }

    public init() {}

    /// Record the state this peer reached. Call after every simulated tick.
    public mutating func record(tick: Tick, hash: UInt64) {
        mine[tick] = hash
        compare(tick: tick)
        prune(before: tick - Self.window)
    }

    /// Record what a peer says it reached. May arrive before or after our own.
    public mutating func received(tick: Tick, hash: UInt64, from peer: PeerName) {
        theirs[peer, default: [:]][tick] = hash
        compare(tick: tick)
    }

    /// Whether every peer that has reported for `tick` agrees with us. Nil when
    /// nobody has reported yet — **not** `true`, because "nobody disagreed" and
    /// "everybody agreed" are different claims and conflating them would let a
    /// silent peer read as a healthy one.
    public func agreement(at tick: Tick) -> Bool? {
        guard let ours = mine[tick] else { return nil }
        let reports = theirs.values.compactMap { $0[tick] }
        guard !reports.isEmpty else { return nil }
        return reports.allSatisfy { $0 == ours }
    }

    /// Peers currently in agreement with us at their most recent shared tick —
    /// the spike's health readout.
    public var agreeingPeers: [PeerName] {
        theirs.keys.filter { peer in
            guard let latest = theirs[peer]?.keys.filter({ mine[$0] != nil }).max() else {
                return false
            }
            return theirs[peer]?[latest] == mine[latest]
        }.sorted()
    }

    private mutating func compare(tick: Tick) {
        guard let ours = mine[tick] else { return }
        // **Earliest tick wins, so reports may arrive in any order.** A peer's
        // hash for tick 40 can turn up after we have already flagged tick 90; the
        // earlier one is the better diagnosis, and keeping the first-seen instead
        // would blame whichever packet happened to land first.
        if let held = firstDivergence, held.tick <= tick { return }
        for (peer, hashes) in theirs.sorted(by: { $0.key < $1.key }) {
            guard let reported = hashes[tick], reported != ours else { continue }
            firstDivergence = Divergence(tick: tick, peer: peer, mine: ours, theirs: reported)
            return
        }
    }

    private mutating func prune(before tick: Tick) {
        guard tick > 0 else { return }
        mine = mine.filter { $0.key >= tick }
        theirs = theirs.mapValues { $0.filter { $0.key >= tick } }
    }
}
