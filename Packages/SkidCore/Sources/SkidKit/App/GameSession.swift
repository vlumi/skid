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

    /// **The networking seam, host-authoritative.**
    ///
    /// Three roles, one class. Local play: `isNetworked` false, nothing here in
    /// use — the loop below is the code that has always shipped. Hosting: the
    /// host IS local play, which is the model's whole point — remote seats'
    /// inputs arrive through the ordinary `inputFor` closure and every tick is
    /// broadcast from `onTick`; nothing in this file knows it is hosting.
    /// Client: `snapshotClient` set, and the sim never runs — the race value
    /// becomes a display buffer for the host's snapshots.
    public var snapshotClient: SnapshotClientDriver?

    /// True for any networked role. The pause guard keys off this (a per-device
    /// pause would freeze one screen of a shared race), as does seat-coloured
    /// rendering.
    public var isNetworked = false

    /// **Which race this session is for.** A rematch builds a new session while the
    /// old one may still be on screen for a frame or two, and both hold the same
    /// driver — so the stale one kept pulling the driver's snapshots for a race that
    /// no longer existed, and the client's car froze at the previous race's last
    /// tick. Reported from device. A session whose generation is stale does nothing.
    public var generation = 0

    /// What a client session needs from the network. `NetworkedGame` conforms.
    @MainActor
    public protocol SnapshotClientDriver: AnyObject {
        /// Seats this device reads thumbs for.
        var mySeats: [PlayerID] { get }
        /// Which race the driver is currently running. A session built for an older
        /// one must not touch it — see `generation`.
        var generation: Int { get }
        /// This frame's thumbs, off to the host. Rate limiting lives behind the
        /// seam — the spike's measured lesson is that MC congests above ~100
        /// small messages a second, so the driver decides which frames send.
        func publish(_ inputs: [PlayerID: CarInput])
        /// The smoothed state to draw, `dt` seconds after the previous frame.
        /// Nil until the first snapshot lands.
        func view(advancedBy dt: TimeInterval) -> RaceSnapshot?
    }

    private var lastTime: TimeInterval?
    private var accumulator: TimeInterval = 0
    /// Don't spiral after a long pause (backgrounding, debugger): cap the
    /// ticks owed by any single frame.
    private static let maxTicksPerFrame = 12

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
        let elapsed = max(0, time - last)
        if let client = snapshotClient {
            advanceClient(by: elapsed, client: client)
            return
        }
        accumulator += elapsed

        var ticks = 0
        while accumulator >= Race.dt, ticks < Self.maxTicksPerFrame {
            step(with: localInputs())
            accumulator -= Race.dt
            ticks += 1
        }
        if ticks == Self.maxTicksPerFrame {
            accumulator = 0
        }
        noteRaceOverIfFinished()
    }

    /// A client frame: thumbs out, the host's state in. No simulation happens
    /// here at all — the race value is a display buffer, `apply` refuses
    /// anything that does not fit it, and there is deliberately no fallback to
    /// simulating locally, because a client treating its own sim as truth is
    /// this model's one unforgivable bug.
    private func advanceClient(by dt: TimeInterval, client: SnapshotClientDriver) {
        // Superseded by a newer race: do nothing at all. Publishing would send this
        // race's thumbs, and consuming would steal the new session's snapshots.
        guard generation == client.generation else { return }
        var mine: [PlayerID: CarInput] = [:]
        for seat in client.mySeats {
            mine[seat] = inputFor(seat, race)
        }
        client.publish(mine)
        if let shown = client.view(advancedBy: dt) {
            race.apply(shown)
            // Skid marks come off the applied states — 60 rendered frames of a
            // 20 Hz stream, so they draw as they do locally. The recording does
            // NOT run on a client: the host records the true race, and a stream
            // of snapshots is not an input recording.
            for car in race.cars {
                marks.record(car: car, on: race.track, tick: race.tick)
            }
            onTick?(race)
        }
        noteRaceOverIfFinished()
    }

    private func localInputs() -> [PlayerID: CarInput] {
        var inputs: [PlayerID: CarInput] = [:]
        for player in players {
            inputs[player] = inputFor(player, race)
        }
        return inputs
    }

    private func noteRaceOverIfFinished() {
        if !raceOver, race.phase == .finished {
            Task { @MainActor [weak self] in
                self?.raceOver = true
            }
        }
    }

    /// One tick, identical for local play and for a host — a hosted race IS a
    /// local race whose remote seats read from the network.
    private func step(with inputs: [PlayerID: CarInput]) {
        recording.append(inputs)
        race.advance(inputs: inputs)
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
