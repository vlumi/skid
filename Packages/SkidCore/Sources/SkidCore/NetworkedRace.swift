import Foundation

/// **One device's view of a race everybody is simulating.**
///
/// The coordinator between the pieces built already: it owns the
/// `LockstepClock` (when a tick may run), the `DivergenceWatch` (do we still
/// agree), and the split between *my thumbs* and *everyone else's inputs*.
///
/// It simulates **every** car, as local play does — that is what inputs-only sync
/// means. The only thing that makes this device special is which seats it reads
/// thumbs for; every other car's input arrives off the wire and is otherwise
/// identical in the sim's eyes.
///
/// Transport-free by construction: it hands out `[UInt8]` to send and takes
/// `[UInt8]` in. No `MCSession`, no socket, no `import MultipeerConnectivity` — so
/// the whole lockstep loop is testable in one process, and the UDP escape hatch
/// stays open.
public struct NetworkedRace: Sendable {
    /// Everyone racing, and which device drives which seat.
    public let roster: RaceRoster
    /// This device — the key into `roster` for "my" seats.
    public let me: RaceRoster.PeerName

    /// Seats this device reads thumbs for.
    public let localSeats: [PlayerID]

    public private(set) var clock: LockstepClock
    public private(set) var watch = DivergenceWatch()

    /// Inputs this device has produced, kept so a packet can carry recent ticks
    /// redundantly. Trimmed to what redundancy needs.
    private var sent: [Tick: [PlayerID: CarInputWire]] = [:]

    public init(roster: RaceRoster, me: RaceRoster.PeerName, delayTicks: Int = 2) {
        self.roster = roster
        self.me = me
        self.localSeats = roster.seats(for: me)
        self.clock = LockstepClock(players: roster.seats, delayTicks: delayTicks)
    }

    // MARK: - Sending

    /// Record this device's own input for a tick, and produce the packet to send.
    ///
    /// **Local input goes through the clock like everybody else's.** It would be
    /// easy — and wrong — to feed local thumbs straight to the sim and only send
    /// them: this device would then run ahead of its own packets and simulate a
    /// different race from every peer. So local input is *received* by the clock
    /// exactly as remote input is, and the delay buffer applies to it equally.
    /// That is also why the input lag is uniform rather than "smooth for me,
    /// laggy for them".
    /// Record this device's input for a tick without producing a packet.
    ///
    /// The newest tick's packet carries the last `Packet.history` ticks, so an older
    /// tick reaches the peer inside it. Sending a packet per tick meant ~100 packets a
    /// second, which backed MultipeerConnectivity's queue up until it choked.
    public mutating func record(_ inputs: [PlayerID: CarInput], at tick: Tick) {
        var quantised: [PlayerID: CarInputWire] = [:]
        for seat in localSeats {
            quantised[seat] = CarInputWire(inputs[seat] ?? .coast)
        }
        sent[tick] = quantised
        clock.receive(LockstepClock.Packet(tick: tick, inputs: [quantised]))
    }

    public mutating func send(_ inputs: [PlayerID: CarInput], at tick: Tick) -> [UInt8] {
        var quantised: [PlayerID: CarInputWire] = [:]
        for seat in localSeats {
            // A seat with no reading coasts. Safe here and only here: this is the
            // device that OWNS the seat, so an absent value means the thumb is off
            // the glass, not that a packet is late.
            quantised[seat] = CarInputWire(inputs[seat] ?? .coast)
        }
        sent[tick] = quantised
        for old in sent.keys where old < tick - LockstepClock.Packet.history {
            sent.removeValue(forKey: old)
        }
        let history = historyEnding(at: tick)
        clock.receive(LockstepClock.Packet(tick: tick, inputs: history))
        return Message.inputs(history, tick: tick, roster: localSeats).encoded
    }

    /// The last `Packet.history` ticks of this device's input, newest first — the
    /// redundancy that repairs a lost packet without anybody asking.
    ///
    /// **Gaps are filled, never skipped.** This used `compactMap`, so a missing tick
    /// silently SHORTENED the array — and since the wire format is positional
    /// (frame *i* means `tick - i`), every frame after the gap was then applied to
    /// the wrong tick by the receiver. Measured: publishing 0,1,2 then 4 produced a
    /// packet whose "tick 3" slot carried tick 2's input. Both peers computed
    /// different states from the same packet, which is the desync reported from
    /// device, and tick 3 never legitimately arrived — hence the constant "waiting".
    ///
    /// A tick this device never published is sent as coast, which is honest: this is
    /// the device that OWNS the seat, so a hole means no reading was taken, and the
    /// alternative is the peers disagreeing about what was.
    private func historyEnding(at tick: Tick) -> [[PlayerID: CarInputWire]] {
        // **Stop at the first hole rather than guessing past it.** Filling a gap with
        // coast is a GUESS, and two peers that guess differently diverge — measured
        // at 80% loss, where the peers disagreed rather than merely falling behind.
        // Truncating keeps the array positional and honest: the receiver simply does
        // not learn about ticks older than the hole, and waits, which is the correct
        // lockstep failure.
        //
        // In practice there are no holes at all: the publisher is gapless by
        // construction (see `GameSession.publishLocalInput`). This is the guard that
        // keeps a future gap from silently corrupting the stream instead.
        var frames: [[PlayerID: CarInputWire]] = []
        for offset in 0..<LockstepClock.Packet.history {
            let at = tick - offset
            guard at >= 0, let frame = sent[at] else { break }
            frames.append(frame)
        }
        return frames
    }

    /// The hash this device reached, to be compared against every peer's.
    public mutating func report(hash: UInt64, at tick: Tick) -> [UInt8] {
        watch.record(tick: tick, hash: hash)
        return Message.hash(hash, tick: tick).encoded
    }

    // MARK: - Receiving

    /// Take a peer's message in. Unknown or malformed bytes are **dropped
    /// silently** rather than thrown: this is data from another device, arriving
    /// 60 times a second, and a single corrupt datagram must not be able to end
    /// the race. `false` is returned so a diagnostic can count them.
    @discardableResult
    public mutating func receive(_ bytes: [UInt8], from peer: RaceRoster.PeerName) -> Bool {
        guard peer != me else { return false }  // our own echo; already applied
        let seats = roster.seats(for: peer)
        guard !seats.isEmpty else { return false }  // not in the roster
        switch Message(bytes: bytes, roster: seats) {
        case .inputs(let frames, let tick, _):
            clock.receive(LockstepClock.Packet(tick: tick, inputs: frames))
            return true
        case .hash(let hash, let tick):
            watch.received(tick: tick, hash: hash, from: peer)
            return true
        case nil:
            return false
        }
    }

    /// A peer left. Its seats stay in the roster and the clock keeps waiting for
    /// them, which is the honest failure mode: the race stalls and says who for.
    /// Deciding to abandon it is a policy question for the UI, not the sim's.
    public mutating func peerLeft(_ peer: RaceRoster.PeerName) {
        stalledOn.formUnion(roster.seats(for: peer))
    }

    /// Seats belonging to peers known to have left — what the UI names when the
    /// race stops moving.
    public private(set) var stalledOn: Set<PlayerID> = []

    // MARK: - Running

    /// The inputs for the next tick, or nil if it is not ready. Feed the result
    /// straight to `Race.advance(inputs:)`, and nothing at all if it is nil.
    public mutating func nextTick() -> [PlayerID: CarInput]? { clock.advance() }

    /// Why the race is not moving, for the diagnostics overlay.
    public var stall: LockstepClock.Stall? { clock.stall }

    /// The first tick two peers disagreed on, if they ever did.
    public var divergence: DivergenceWatch.Divergence? { watch.firstDivergence }

    // MARK: - Wire messages

    /// Everything a peer sends, in one byte-tagged envelope.
    ///
    /// Two message kinds only — inputs and a state hash. Everything else the
    /// design needs (the roster, the track, the seed) is agreed **once** before
    /// the race and belongs to the lobby, not to a 60 Hz channel.
    enum Message {
        /// `roster` is the SENDER's seats — the positional key the payload is
        /// written against, and what the receiver must decode with. Carried in the
        /// case rather than assumed, because encode and decode use different
        /// rosters: mine when sending, theirs when receiving.
        case inputs([[PlayerID: CarInputWire]], tick: Tick, roster: [PlayerID])
        case hash(UInt64, tick: Tick)

        private static let inputsTag: UInt8 = 1
        private static let hashTag: UInt8 = 2

        var encoded: [UInt8] {
            switch self {
            case .inputs(let frames, let tick, let roster):
                return [Self.inputsTag]
                    + LockstepClock.Packet(tick: tick, inputs: frames).encoded(roster: roster)
            case .hash(let hash, let tick):
                var out = [Self.hashTag]
                withUnsafeBytes(of: Int32(tick).littleEndian) { out.append(contentsOf: $0) }
                withUnsafeBytes(of: hash.littleEndian) { out.append(contentsOf: $0) }
                return out
            }
        }

        init?(bytes: [UInt8], roster: [PlayerID]) {
            guard let tag = bytes.first else { return nil }
            let body = Array(bytes.dropFirst())
            switch tag {
            case Self.inputsTag:
                guard let packet = LockstepClock.Packet(bytes: body, roster: roster) else {
                    return nil
                }
                self = .inputs(packet.inputs, tick: packet.tick, roster: roster)
            case Self.hashTag:
                guard body.count == 12 else { return nil }
                var tickBits: Int32 = 0
                var hashBits: UInt64 = 0
                withUnsafeMutableBytes(of: &tickBits) { $0.copyBytes(from: body[0..<4]) }
                withUnsafeMutableBytes(of: &hashBits) { $0.copyBytes(from: body[4..<12]) }
                self = .hash(
                    UInt64(littleEndian: hashBits), tick: Tick(Int32(littleEndian: tickBits)))
            default:
                return nil  // a future message kind; ignore rather than fail
            }
        }
    }

}
