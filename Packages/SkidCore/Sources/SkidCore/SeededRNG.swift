/// Deterministic RNG (SplitMix64). All randomness in the sim must come from
/// an injected instance of this, seeded per race, so races are reproducible
/// bit-for-bit in tests, replays, and (later) lockstep networking.
public struct SeededRNG: RandomNumberGenerator, Equatable, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
