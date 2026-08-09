import Foundation
import SkidCore

/// Drives the deterministic sim from render-loop time: accumulates elapsed
/// wall time and steps the race at its fixed timestep, however many ticks a
/// frame owes. Rendering reads the latest state; per-player input comes
/// from the injected provider — the sim never knows which scheme or finger
/// produced it.
///
/// One session = one race. "Race again" builds a fresh session (new seed),
/// so recording/marks/timing state can never leak between runs.
///
/// Deliberately no `@Published`: the game view redraws every frame via
/// `TimelineView(.animation)` anyway, and publishing per-frame sim state
/// would mutate observable state mid-view-update.
@MainActor
public final class GameSession: ObservableObject {
    public private(set) var race: Race
    public private(set) var marks = MarkStore()
    /// The whole run as seed + inputs — replay/ghost currency, recorded
    /// from the first lap-capable build because it can't be retrofitted.
    public private(set) var recording: RaceRecording
    /// Where each gate paints its checkpoint line on the road.
    public let gateSpans: [(a: Vec2, b: Vec2)?]

    public let players: [PlayerID]
    /// The PB ghost running alongside, if any (time trial).
    public let ghost: GhostPlayback?
    /// Frozen: the sim doesn't advance and the clock doesn't accumulate.
    /// Published (unlike per-frame state) so chrome like edge-gesture
    /// deferral can react — it only flips on explicit user action.
    @Published public var paused = false
    /// The race waits on a ready gate: it opens frozen (everyone gets thumbs
    /// in place) and only begins once a player taps to start. Freezing before
    /// the countdown reuses the exact `paused` mechanism (clock stays
    /// anchored), so the countdown then runs cleanly from tick 0.
    ///
    /// **A networked race starts itself** — see `lockstep`. The gate is per-device,
    /// so waiting for a tap on each screen deadlocks: a device that has not started
    /// publishes no input, so no peer's clock can release a tick, so nobody's
    /// countdown moves. It stuck at "3" on two phones. The host's "Start race" in
    /// the lobby IS the shared ready gate, and it is the only one there can be.
    @Published public var started = false
    /// Called after every sim tick with the fresh race — the event stream
    /// consumer seam (sound, haptics). Events from intermediate ticks in a
    /// frame are never skipped.
    public var onTick: ((Race) -> Void)?
    /// Published once when the race reaches .finished — chrome outside the
    /// per-frame redraw (edge-gesture deferral) keys off this. Set via a
    /// hop off the render pass, never mid-view-update.
    @Published public private(set) var raceOver = false
    private let inputFor: (PlayerID, Race) -> CarInput

    /// **The lockstep driver, when this race is networked.**
    ///
    /// Nil for local play, and that is the whole design of this seam: the local
    /// path below is byte-for-byte the code that shipped, so wiring networking
    /// cannot regress a couch race. Set it and the *condition for running a tick*
    /// changes from "wall time owes one" to "wall time owes one AND every peer's
    /// input for it has arrived".
    public var lockstep: LockstepDriver? {
        didSet {
            // Networked: the lobby already gated the start, so open the local gate
            // immediately. Leaving it shut is a deadlock rather than a delay,
            // because a frozen device never publishes the input its peers need.
            if lockstep != nil { started = true }
        }
    }

    /// What `GameSession` needs from the network, kept to three calls so the
    /// session never learns what a peer is. `NetworkedGame` conforms.
    @MainActor
    public protocol LockstepDriver: AnyObject {
        /// Seats this device reads thumbs for. Others' inputs arrive off the wire.
        var mySeats: [PlayerID] { get }
        /// Publish this device's own input for `tick`.
        func publish(_ inputs: [PlayerID: CarInput], at tick: Tick)
        /// How far ahead of the sim this device publishes — the delay buffer. Read
        /// rather than assumed, so the session cannot disagree with the clock about
        /// which tick an input belongs to.
        var delayTicks: Int { get }
        /// The next tick's inputs, or nil to wait. **Nil means do not step.**
        func nextTick() -> [PlayerID: CarInput]?
        /// Tell peers what state we reached, so a divergence is caught.
        func report(hash: UInt64, at tick: Tick)
    }

    /// The newest tick this device has published input for. Only used to avoid
    /// publishing the same tick twice — the tick itself is derived from `race.tick`,
    /// never counted, so two peers cannot disagree about which tick a press belongs
    /// to. See `inputsForNextTick()`.
    private var lastPublished: Tick = -1

    private var lastTime: TimeInterval?
    private var accumulator: TimeInterval = 0
    /// Don't spiral after a long pause (backgrounding, debugger): cap the
    /// ticks owed by any single frame.
    private static let maxTicksPerFrame = 12

    /// Owed sim time past which a networked race abandons its backlog — a second,
    /// comfortably more than any stall the delay buffer is meant to absorb and far
    /// less than a backgrounded app accrues.
    private static let maxNetworkedDebt: TimeInterval = 1.0

    public init(
        track: Track,
        players: [PlayerID],
        config: RaceConfig,
        seed: UInt64,
        tuning: CarTuning = CarTuning(),
        ghost: GhostPlayback? = nil,
        inputFor: @escaping (PlayerID, Race) -> CarInput
    ) {
        self.players = players
        self.inputFor = inputFor
        self.ghost = ghost
        self.race = Race(
            track: track, players: players, tuning: tuning, seed: seed, config: config)
        self.recording = RaceRecording(seed: seed, players: players)
        self.gateSpans = track.gates.map { track.ribbonSpan(of: $0) }
    }

    /// Advance sim time to `time` (a `TimelineView` timestamp, seconds).
    public func advance(to time: TimeInterval) {
        if paused || !started {
            // Frozen (paused, or waiting on the ready gate): keep the wall
            // clock anchored so starting/resuming doesn't owe a burst of ticks.
            lastTime = time
            return
        }
        guard let last = lastTime else {
            lastTime = time
            return
        }
        lastTime = time
        accumulator += max(0, time - last)

        var ticks = 0
        while accumulator >= Race.dt, ticks < Self.maxTicksPerFrame {
            guard let inputs = inputsForNextTick() else {
                // **Networked and not ready: stop, keeping the debt.** The
                // accumulator is deliberately NOT drained — the ticks are still
                // owed and will run as soon as the inputs land, which is what
                // turns packet loss into lag rather than into a race that
                // silently skipped part of itself.
                break
            }
            step(with: inputs)
            accumulator -= Race.dt
            ticks += 1
        }
        if ticks == Self.maxTicksPerFrame {
            accumulator = 0
        }
        // **A networked race keeps a short debt but drops a hopeless one.**
        //
        // A brief stall must keep what it owes: that is exactly how packet loss
        // becomes input lag instead of a race that silently skipped part of itself,
        // and `testAStalledNetworkFreezesTheSimWithoutLosingTheDebt` pins it.
        //
        // But backgrounding stops the render loop entirely, so nothing publishes,
        // every peer stalls, and returning owes *seconds* of ticks that
        // `maxTicksPerFrame` can never work through — the race looks permanently
        // stuck. Lockstep keeps the peers in step by construction, so wall-clock
        // debt past a second is not information, it is a backlog. Drop it and run at
        // whatever rate the clock releases ticks.
        if lockstep != nil, accumulator > Self.maxNetworkedDebt {
            accumulator = 0
        }
        if !raceOver, race.phase == .finished {
            Task { @MainActor [weak self] in
                self?.raceOver = true
            }
        }
    }

    /// This tick's inputs — from local controls, or from the lockstep clock.
    ///
    /// Nil only ever means "networked, and the tick is not ready". Local play
    /// always has an answer, because a thumb that is not touching the glass is a
    /// coast rather than a missing input.
    private func inputsForNextTick() -> [PlayerID: CarInput]? {
        guard let lockstep else {
            var inputs: [PlayerID: CarInput] = [:]
            for player in players {
                inputs[player] = inputFor(player, race)
            }
            return inputs
        }
        // Read our own thumbs and publish them, then take whatever the clock
        // releases — which may be a tick whose inputs arrived several frames ago.
        //
        // **The tick we publish for is derived from the SIM, not counted locally.**
        // A local counter incremented once per attempt drifts: this loop runs on
        // every frame, including the ones that stall, so a device that waited 19
        // ticks published 50 inputs for 31 simulated ticks (measured). Each peer's
        // counter then drifts by however much IT stalled, so the same thumb press
        // is labelled tick 40 on one device and tick 31 on the other — the cars
        // then genuinely diverge, which is what the hash comparison correctly
        // reported. Reported from device as a ~200-unit positional offset.
        //
        // `race.tick` plus the buffer is the one value both peers agree on, because
        // it comes from the shared simulation rather than from local wall time.
        let publishFor = race.tick + lockstep.delayTicks
        guard publishFor > lastPublished else { return lockstep.nextTick() }
        var mine: [PlayerID: CarInput] = [:]
        for seat in lockstep.mySeats {
            mine[seat] = inputFor(seat, race)
        }
        lockstep.publish(mine, at: publishFor)
        lastPublished = publishFor
        return lockstep.nextTick()
    }

    /// One tick, identical whether the inputs came from thumbs or the wire.
    ///
    /// Shared on purpose: two copies of this would be the hardest kind of bug to
    /// find, since a networked race would diverge from a local one for a reason
    /// invisible in both.
    private func step(with inputs: [PlayerID: CarInput]) {
        recording.append(inputs)
        race.advance(inputs: inputs)
        lockstep?.report(hash: race.stateHash, at: race.tick)
        ghost?.advanceTick()
        for car in race.cars {
            marks.record(car: car, on: race.track, tick: race.tick)
        }
        onTick?(race)
    }
}

/// mm:ss.hh from a tick count, for lap/race times.
public func formatTicks(_ ticks: Tick) -> String {
    let totalHundredths = ticks * 100 / Race.tickRate
    let minutes = totalHundredths / 6000
    let seconds = (totalHundredths % 6000) / 100
    let hundredths = totalHundredths % 100
    return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
}

/// Race position as a locale-aware ordinal ("1st", "2nd", …) — distinct from
/// the "P1/P2" that identifies a *player*, so the two never read alike.
public func ordinal(_ place: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal
    return formatter.string(from: NSNumber(value: place)) ?? "\(place)"
}
