import Foundation

/// **The lockstep clock: when a tick is allowed to run.**
///
/// Everything about networked racing that can be wrong in an interesting way is
/// here, and none of it needs a socket. `GameSession` today runs a tick whenever
/// wall time owes one; lockstep replaces that with "…and every peer's input for
/// that tick has arrived". The consequences are the whole design:
///
/// - **A tick cannot be skipped.** Every peer must have every player's input for
///   tick N before any of them may simulate it, so a lost packet is not a glitch
///   or a rubber-band — it is a *stall*, and every car freezes until the input
///   arrives. That is the trade lockstep makes: it never lies about the world, it
///   sometimes waits. Four people on a couch watching one race would rather
///   everything pause for 50 ms than see four different opinions about where the
///   cars are.
/// - **Loss is repaired by redundancy, not retransmission.** Inputs are tiny and
///   idempotent, so a packet carries the last few ticks as well as the newest
///   (`Packet.history`). One lost packet is repaired by the next one ~16 ms later
///   without anybody asking for it.
/// - **The delay buffer converts loss into latency.** Running a fixed few ticks
///   behind the newest input gives a late packet time to arrive before its tick is
///   needed, turning visible stalls into *constant* input lag. It is the single
///   most important tuning knob and the one thing here that a test cannot settle:
///   what `delayTicks` should be is a question about feel, and it goes on device.
///
/// Deliberately transport-free. It never mentions MultipeerConnectivity, a peer
/// address or a socket — it consumes `Packet`s and answers questions about ticks.
/// That is what lets the escape hatch (UDP via Network.framework) stay open, and
/// what lets all of the above be tested in one process.
public struct LockstepClock: Sendable {
    /// How far behind the newest received input the sim runs.
    ///
    /// **Tune on device, not here.** 2–4 ticks is 33–66 ms of input lag, and the
    /// drift model is twitchy enough that the cost may be more noticeable than in
    /// a slower game. Zero is legal and means "no buffer": every packet must
    /// arrive before its tick or everyone stalls.
    public let delayTicks: Int

    /// Seats this clock waits for. A peer owning several seats sends them
    /// together, but the clock cares about seats rather than devices — which is
    /// what makes "two phones with two players each" ordinary rather than special.
    public let players: [PlayerID]

    /// The next tick to simulate. Ticks are simulated strictly in order.
    public private(set) var tick: Tick = 0

    /// Inputs received but not yet consumed, by tick. Sparse on purpose: a peer
    /// may be several ticks ahead, and ticks arrive out of order.
    private var pending: [Tick: [PlayerID: CarInputWire]] = [:]

    /// The newest tick any peer has sent anything for — what `delayTicks` is
    /// measured back from.
    public private(set) var newestReceived: Tick = -1

    public init(players: [PlayerID], delayTicks: Int = 2) {
        self.players = players
        self.delayTicks = max(0, delayTicks)
    }

    // MARK: - Receiving

    /// One peer's inputs for one or more ticks. Carries `history` older ticks
    /// redundantly, so a single loss costs nothing.
    public struct Packet: Equatable, Sendable, Codable {
        /// The newest tick in this packet.
        public var tick: Tick
        /// Inputs for `tick`, then `tick - 1`, and so on — newest first. A packet
        /// covering ticks 9, 8 and 7 has three entries.
        public var inputs: [[PlayerID: CarInputWire]]

        /// How many ticks of redundancy to carry.
        ///
        /// **Three was badly wrong.** At 60 Hz it survives 33 ms of loss, and real
        /// Wi-Fi on a phone loses bursts far longer — measured in a test at 20%
        /// loss, one peer reached tick 150 while the other reached 22. "More than
        /// enough on a couch network" was an assumption dressed as a measurement.
        ///
        /// Twenty ticks is a third of a second of cover, at 4 bytes per seat per
        /// tick: 80 bytes per seat, ~170 for a two-seat device, still one small
        /// datagram. Redundancy is the *only* repair mechanism here — there is no
        /// retransmission — so it should be sized to the worst burst worth
        /// surviving, not the cheapest one.
        public static let history = 20

        public init(tick: Tick, inputs: [[PlayerID: CarInputWire]]) {
            self.tick = tick
            self.inputs = inputs
        }

        // MARK: - The compact form

        /// The packet as bytes: `tick` then every seat's four bytes, **positionally
        /// against `roster`**.
        ///
        /// `Codable` is not a wire format. Measured: two seats × three ticks is 28
        /// bytes of payload and 438 bytes of JSON, because every seat's id is
        /// spelled out as a dictionary key on every tick — 26 KB/s per peer at
        /// 60 Hz for data that fits in 1.7. Naming the seats once, in the roster
        /// both peers agreed at join time, is what removes that.
        ///
        /// A seat missing from `inputs` is sent as coast. That is safe here and
        /// nowhere else: a *sender* always has its own seats' input, so a hole
        /// means "this peer does not own that seat", and the roster passed in is
        /// the sender's own. It is emphatically not the receiver's licence to
        /// invent a coast for a late packet — see `advance()`.
        public func encoded(roster: [PlayerID]) -> [UInt8] {
            var out: [UInt8] = []
            out.reserveCapacity(5 + roster.count * inputs.count * CarInputWire.byteCount)
            withUnsafeBytes(of: Int32(tick).littleEndian) { out.append(contentsOf: $0) }
            // **The seat count is on the wire, and length alone cannot replace it.**
            // A 24-byte payload divides evenly by both a 2-seat roster (3 frames)
            // and a 3-seat one (2 frames), so a roster mismatch decoded cleanly and
            // invented inputs for a seat that never sent any. Found by the test that
            // expected it to be rejected.
            out.append(UInt8(truncatingIfNeeded: roster.count))
            for frame in inputs {
                for seat in roster {
                    out.append(contentsOf: (frame[seat] ?? CarInputWire(.coast)).bytes)
                }
            }
            return out
        }

        /// Rebuild from `encoded(roster:)`. Nil on any malformed length — a peer
        /// sending garbage must be dropped rather than partially believed.
        public init?(bytes: [UInt8], roster: [PlayerID]) {
            let stride = roster.count * CarInputWire.byteCount
            guard !roster.isEmpty, bytes.count > 5, bytes[4] == UInt8(roster.count),
                (bytes.count - 5) % stride == 0
            else { return nil }
            var tickBits: Int32 = 0
            withUnsafeMutableBytes(of: &tickBits) { $0.copyBytes(from: bytes[0..<4]) }
            tick = Tick(Int32(littleEndian: tickBits))
            var frames: [[PlayerID: CarInputWire]] = []
            var offset = 5
            while offset < bytes.count {
                var frame: [PlayerID: CarInputWire] = [:]
                for seat in roster {
                    let end = offset + CarInputWire.byteCount
                    // **Belt and braces, deliberately.** The length guard above
                    // already rejects a clipped datagram, so this is unreachable
                    // today — and it stays because slicing past the end TRAPS, and
                    // the two together mean a bug in that arithmetic degrades to a
                    // dropped packet instead of a crash. Verified by sabotage:
                    // removing either alone is safe, removing both is a fatal.
                    guard end <= bytes.count,
                        let input = CarInputWire(bytes: bytes[offset..<end])
                    else { return nil }
                    frame[seat] = input
                    offset = end
                }
                frames.append(frame)
            }
            inputs = frames
        }
    }

    /// Take a packet in. Older ticks it carries are merged, ticks already
    /// consumed are ignored, and a seat that arrives twice keeps the first value
    /// — see `receive(_:for:)`.
    public mutating func receive(_ packet: Packet) {
        for (offset, seats) in packet.inputs.enumerated() {
            let at = packet.tick - offset
            for (player, input) in seats { receive(input, for: player, at: at) }
        }
        newestReceived = max(newestReceived, packet.tick)
    }

    /// One seat's input for one tick.
    ///
    /// **First value wins, and that is load-bearing.** Redundant packets mean the
    /// same (tick, seat) arrives repeatedly; if a later copy could overwrite an
    /// earlier one, two peers that received the copies in a different order would
    /// simulate different races. Idempotence is what makes redundancy safe.
    public mutating func receive(_ input: CarInputWire, for player: PlayerID, at when: Tick) {
        guard when >= tick else { return }  // already simulated; the past is settled
        pending[when, default: [:]][player] = pending[when]?[player] ?? input
        newestReceived = max(newestReceived, when)
    }

    // MARK: - Running

    /// Whether tick `tick` may be simulated now: every seat's input is in hand,
    /// **and** the delay buffer has the slack it asked for.
    public var canAdvance: Bool {
        guard tick + delayTicks <= newestReceived else { return false }
        return haveAllInputs(for: tick)
    }

    /// Why the sim is not advancing — for the spike's log and the "waiting for
    /// players" chrome. A stall with a named cause is a measurement; a frozen
    /// screen is a bug report.
    public enum Stall: Equatable, Sendable {
        /// Named seats have not sent this tick yet.
        case waitingForInput(tick: Tick, missing: [PlayerID])
        /// Everyone's input is here, but the clock is holding it back so late
        /// packets have room. Normal, and what makes loss feel like lag.
        case buffering(tick: Tick, ticksBehind: Int)
    }

    public var stall: Stall? {
        guard !canAdvance else { return nil }
        let missing = missingInputs(for: tick)
        if missing.isEmpty {
            return .buffering(tick: tick, ticksBehind: newestReceived - tick)
        }
        return .waitingForInput(tick: tick, missing: missing)
    }

    /// Consume the current tick's inputs and step the clock forward.
    ///
    /// Returns nil rather than an empty dictionary when the tick is not ready:
    /// the caller must not step the sim, and a missing input is emphatically not
    /// "everybody coasts" — that would be a peer inventing a different race.
    public mutating func advance() -> [PlayerID: CarInput]? {
        guard canAdvance else { return nil }
        let wire = pending.removeValue(forKey: tick) ?? [:]
        tick += 1
        return wire.mapValues(\.input)
    }

    // MARK: - Inspection

    private func haveAllInputs(for tick: Tick) -> Bool {
        guard let seats = pending[tick] else { return players.isEmpty }
        return players.allSatisfy { seats[$0] != nil }
    }

    private func missingInputs(for tick: Tick) -> [PlayerID] {
        let seats = pending[tick] ?? [:]
        return players.filter { seats[$0] == nil }.sorted()
    }

    /// How many ticks of input are buffered ahead of the sim — the spike's health
    /// readout. Growing means this peer is falling behind; zero means it is
    /// starved and about to stall.
    public var bufferedTicks: Int {
        max(0, newestReceived - tick + 1)
    }

    /// Ticks currently held, for tests and the spike's diagnostics. Nothing at or
    /// before `tick` may appear here: the past is settled, and a stale redundant
    /// copy that lodged in the buffer would sit there for the rest of the race.
    public var heldTicks: [Tick] { pending.keys.sorted() }
}
