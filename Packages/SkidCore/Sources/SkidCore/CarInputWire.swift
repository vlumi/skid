import Foundation

/// **`CarInput` as four bytes, and as the only values the sim ever steps from.**
///
/// A `CarInput` is three `Double`s — 24 bytes, and a needlessly exact thing for
/// two devices to agree about. Quantising it to four bytes is the smaller half of
/// the win; the real one is that a `Double` produced by a thumb on one phone and
/// the `Double` reconstructed on another are then *the same number by
/// construction*, rather than two float paths hoping to agree.
///
/// **The rule that makes it work: quantise locally too.** A peer that sends
/// quantised input while stepping its own raw thumb value has two different races
/// and will diverge — slowly, invisibly, and for a reason that looks like a
/// physics bug. So `CarInput.quantised` exists to be applied on the way *into* the
/// sim, not only on the way onto the wire, and the round trip is deliberately
/// lossy in the same way everywhere.
///
/// **Not yet applied to `RaceRecording`.** The plan bills smaller ghosts as a free
/// side-effect of this encoding, and the 6× is real — but recordings are persisted
/// inside `Hiscores`, so changing their stored format invalidates every existing
/// ghost. That is a migration rather than a freebie, and it belongs with whatever
/// else touches the hiscore file.
public struct CarInputWire: Equatable, Sendable, Codable {
    /// steer, throttle: one byte each. aim: two, plus its presence.
    public static let byteCount = 4

    private var steerByte: Int8
    private var throttleByte: Int8
    /// `nil` is a real value here — the steer channel, not "aim of zero", which
    /// is a car pointed east. Sent as one reserved bit pattern rather than a
    /// fifth byte (see `aimUnset`).
    private var aimUnits: UInt16

    /// The one pattern of 65 536 that means "no aim". Costs a hair of aim
    /// precision (the sim wraps, so the lost angle is indistinguishable from its
    /// neighbor) and saves a whole byte on every packet of every tick.
    private static let aimUnset = UInt16.max
    private static let aimSteps = Double(UInt16.max)  // 65 535 usable, 0 … max-1

    public init(_ input: CarInput) {
        steerByte = Self.encode(unit: input.steer)
        throttleByte = Self.encode(unit: input.throttle)
        aimUnits = input.aim.map(Self.encode(angle:)) ?? Self.aimUnset
    }

    public var input: CarInput {
        CarInput(
            steer: Self.decode(unit: steerByte),
            throttle: Self.decode(unit: throttleByte),
            aim: aimUnits == Self.aimUnset ? nil : Self.decode(angle: aimUnits))
    }

    // MARK: - The axes

    /// −1…1 across `Int8`, **symmetrically**: 127 steps each way, with −128
    /// unused. The lopsided alternative (−128…127) cannot represent center and
    /// full-left with the same step size, so a stick held dead center would
    /// quantise to a slight turn — the one value that must survive exactly.
    private static func encode(unit value: Double) -> Int8 {
        // **NaN has to be handled explicitly.** `max(-1, min(1, nan))` is `nan` in
        // Swift, and `Int8(nan.rounded())` traps — so a malformed value reaching
        // here would crash rather than produce a wrong car. `value.isFinite`
        // rather than `!isNaN` because an infinity would also fail the conversion.
        guard value.isFinite else { return 0 }
        let clamped = max(-1, min(1, value))
        return Int8((clamped * 127).rounded())
    }

    private static func decode(unit byte: Int8) -> Double {
        Double(byte) / 127
    }

    /// A heading as a fraction of a full turn. **Absolute range needs no
    /// agreement**: the sim consumes aim only as `atan2(sin(aim - heading),
    /// cos(aim - heading))`, so it is a direction on a circle and wrapping is
    /// free. π and −π are the same command and quantise to the same byte pair,
    /// which is correct rather than a rounding artefact.
    ///
    /// 65 535 steps over a full turn is 0.0000959 rad — about 0.0055°, some three
    /// orders finer than a thumb on glass resolves.
    private static func encode(angle radians: Double) -> UInt16 {
        // Same trap as the axes: a non-finite angle cannot become a UInt16.
        // Falls back to the reserved pattern — an unusable aim is no aim, which
        // hands the car to the steer channel rather than pointing it at NaN.
        guard radians.isFinite else { return aimUnset }
        let turns = radians / (2 * .pi)
        let wrapped = turns - (turns.rounded(.down))  // 0 … 1
        let units = (wrapped * aimSteps).rounded()
        // A hair below a full turn rounds up INTO the reserved pattern; it means
        // the same direction as zero, so it belongs there.
        return units >= aimSteps ? 0 : UInt16(units)
    }

    private static func decode(angle units: UInt16) -> Double {
        Double(units) / aimSteps * 2 * .pi
    }
}

extension CarInput {
    /// This input as the sim must see it — **the wire value, decoded back**.
    ///
    /// Apply this to local input as well as received input. Two peers stepping
    /// the same quantised numbers agree by construction; a peer stepping its own
    /// raw thumb value against a neighbor's quantised one does not.
    public var quantised: CarInput { CarInputWire(self).input }
}

extension CarInputWire {
    /// The four bytes themselves, for a packet that wants to be four bytes.
    ///
    /// **`Codable` is not a wire format.** A `Packet` of two seats × three ticks
    /// is 28 bytes of payload and encodes to 438 bytes of JSON — 15× — because
    /// every seat's id is spelled out as a dictionary key on every tick. At 60 Hz
    /// that is 26 KB/s per peer for data that fits in 1.7. Measured, not guessed.
    ///
    /// So the packet encodes seats *positionally* against an agreed roster and
    /// concatenates these bytes. Little-endian is stated rather than assumed: the
    /// bytes cross a network, and both current peers being arm64 is a fact about
    /// today's hardware, not about the format.
    public var bytes: [UInt8] {
        [
            UInt8(bitPattern: steerByte), UInt8(bitPattern: throttleByte),
            UInt8(truncatingIfNeeded: aimUnits), UInt8(truncatingIfNeeded: aimUnits >> 8),
        ]
    }

    /// Rebuild from `bytes`. Nil if the slice is the wrong length — a malformed
    /// packet must be dropped, not guessed at.
    public init?(bytes: ArraySlice<UInt8>) {
        guard bytes.count == CarInputWire.byteCount else { return nil }
        var iterator = bytes.makeIterator()
        guard
            let steer = iterator.next(), let throttle = iterator.next(),
            let low = iterator.next(), let high = iterator.next()
        else { return nil }
        steerByte = Int8(bitPattern: steer)
        throttleByte = Int8(bitPattern: throttle)
        aimUnits = UInt16(low) | (UInt16(high) << 8)
    }
}
