import Foundation

/// **A bit-exact fingerprint of the simulation's state.**
///
/// The one measurement lockstep networking rests on: two peers stepping the same
/// inputs must reach the same state, and a hash per tick is how that is *checked*
/// rather than hoped for. It answers "do we still agree?" in eight bytes, and
/// "since when?" the moment two sequences are compared.
///
/// It is useful before any networking exists. The existing determinism tests assert
/// `XCTAssertEqual(a, b)` over two whole races, which says *that* they differ and
/// never *when* — the difference between a five-minute and a five-hour debug session.
///
/// **Why a hash and not `Codable`.** `Race` is deliberately not encodable: a summary
/// invites comparison, whereas a serialised race invites *sending* it, which is the
/// opposite of inputs-only sync. Anything that makes shipping state easy is a
/// liability in a design whose whole safety comes from shipping only inputs.
extension Race {
    /// The state after the current tick, as a 64-bit digest.
    ///
    /// **Every field that physics reads, and nothing else.** Not a hand-picked
    /// subset: a partial digest is worse than none, because it lets real divergence
    /// pass unnoticed and so *earns* trust it does not have. `steerActuator` is a
    /// good example of why — it looks like a rendering detail and is in fact carried
    /// state, so a car whose wheel is mid-turn differs from one whose is not.
    ///
    /// **Two things are excluded, both outputs rather than state.** `lastEvents` is
    /// derived fresh each tick for sound and haptics, and `CarState.wallContact` is
    /// the debug overlay's readout — checked, not assumed: every read of it is
    /// `RaceWalls` reading back its own accumulator, and none of it reaches
    /// position, velocity or heading. Peers that agree on state agree on both.
    ///
    /// The distinction matters in one direction only. Hashing an output risks a
    /// *false* divergence — peers halting over a haptics counter — while missing
    /// real state hides the failure this exists to find. So when a new field is
    /// ambiguous, hash it.
    public var stateHash: UInt64 {
        var hash = Hasher64()
        hash.combine(tick)
        for car in cars {
            hash.combine(car.id.rawValue)
            hash.combine(car.state.position.x)
            hash.combine(car.state.position.y)
            hash.combine(car.state.velocity.x)
            hash.combine(car.state.velocity.y)
            hash.combine(car.state.heading)
            hash.combine(car.state.height)
            hash.combine(car.state.airborneTicks)
            hash.combine(car.state.verticalSpeed)
            hash.combine(car.state.steerActuator)
            hash.combine(car.progress.nextGate)
            hash.combine(car.progress.lap)
            hash.combine(car.progress.lapStartTick)
            hash.combine(car.progress.finishedAt ?? -1)
            for time in car.progress.lapTimes { hash.combine(time) }
        }
        return hash.value
    }
}

/// **FNV-1a, spelled out rather than borrowed.**
///
/// Swift's own `Hasher` is explicitly seeded per process and its output is *not*
/// stable across runs or platforms — which is exactly the property this must not
/// have. A hash used to compare two devices has to be reproducible by construction,
/// so it is written here where the arithmetic is visible.
///
/// Not a cryptographic hash and not trying to be: the threat is a physics
/// divergence in the last bits of a `Double`, not an adversary crafting a collision.
struct Hasher64 {
    static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    static let prime: UInt64 = 0x0000_0100_0000_01b3

    private(set) var value = Hasher64.offsetBasis

    /// One byte: XOR then multiply, which is FNV-1a in full.
    ///
    /// **Deliberately not an overload of `combine`.** `combine(UInt8(0))` resolved
    /// to the `UInt64` version through implicit conversion and hashed eight bytes
    /// instead of one — silently, since both compile and both return a plausible
    /// number. An overload set whose members disagree about how much they consume
    /// is a trap, so the widths get distinct names and only `combine` is offered
    /// to callers.
    mutating func combineByte(_ byte: UInt8) {
        value ^= UInt64(byte)
        value = value &* Self.prime
    }

    mutating func combine(_ bits: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            combineByte(UInt8(truncatingIfNeeded: bits >> UInt64(shift)))
        }
    }

    mutating func combine(_ number: Int) {
        combine(UInt64(bitPattern: Int64(number)))
    }

    /// A `Double` by its **bit pattern**, which is the whole point: comparing the
    /// bits catches a divergence in the last place, where comparing rounded values
    /// would hide precisely the failure this exists to find.
    ///
    /// Zero is normalised because IEEE-754 has two of them: `-0.0` and `0.0` are
    /// equal as numbers and differ in bits, so a car that stopped from the left
    /// would otherwise hash differently from one that stopped from the right.
    mutating func combine(_ double: Double) {
        combine((double == 0 ? 0 : double).bitPattern)
    }
}
