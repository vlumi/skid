import Foundation

/// **The host's word on where everything is.**
///
/// Under host-authoritative networking one device simulates the race and the
/// rest render it. This is what travels: per car, the fields the renderer and
/// HUD actually read — nothing the client would simulate with, because the
/// client does not simulate.
///
/// The old rule ("never serialise the race, a summary invites comparison but a
/// serialised race invites sending it") belonged to lockstep, where sending
/// state was the cardinal sin. Under a host authority it inverts: sending state
/// is the whole design, and what must NOT happen is a client treating its own
/// sim as truth. Divergence is impossible by construction — there is nothing to
/// diverge from.
///
/// Sized for the wire: ~35 bytes per car as `Float32`, which is plenty for
/// rendering (the client never does physics on these numbers). A nine-car field
/// stays inside a single datagram at any sane snapshot rate.
public struct RaceSnapshot: Equatable, Sendable {
    public struct CarEntry: Equatable, Sendable {
        public var seat: PlayerID
        public var position: Vec2
        public var velocity: Vec2
        public var heading: Double
        public var height: Double
        public var steerActuator: Double
        public var airborne: Bool
        public var progress: CarProgress
    }

    /// The host's sim tick when this was taken. Clients derive the countdown and
    /// lap timers from it, so it must be the real one.
    public var tick: Tick
    public var cars: [CarEntry]

    public init(of race: Race) {
        tick = race.tick
        cars = race.cars.map { car in
            CarEntry(
                seat: car.id,
                position: car.state.position,
                velocity: car.state.velocity,
                heading: car.state.heading,
                height: car.state.height,
                steerActuator: car.state.steerActuator,
                airborne: car.state.isAirborne,
                progress: car.progress)
        }
    }

    init(tick: Tick, cars: [CarEntry]) {
        self.tick = tick
        self.cars = cars
    }
}

extension Race {
    /// Adopt the host's state. The client's own race value is a *display buffer*:
    /// nothing on the client simulates, so overwriting is safe and total.
    ///
    /// Seats are verified per entry rather than trusted by position — the roster
    /// work already caught one silent misalignment (a 24-byte payload that decoded
    /// cleanly against the wrong seat count), and a snapshot applied to the wrong
    /// cars would be that bug again, painted on screen.
    public mutating func apply(_ snapshot: RaceSnapshot) {
        guard snapshot.cars.count == cars.count else { return }
        for (index, entry) in snapshot.cars.enumerated() {
            guard cars[index].id == entry.seat else { return }
        }
        tick = snapshot.tick
        for (index, entry) in snapshot.cars.enumerated() {
            cars[index].state.position = entry.position
            cars[index].state.velocity = entry.velocity
            cars[index].state.heading = entry.heading
            cars[index].state.height = entry.height
            cars[index].state.steerActuator = entry.steerActuator
            cars[index].state.airborneTicks = entry.airborne ? 1 : 0
            cars[index].progress = entry.progress
        }
    }
}

extension RaceSnapshot {
    /// A state between two snapshots, for rendering at more frames than the host
    /// sends. Continuous quantities blend; discrete ones (progress, airborne) jump
    /// at the later snapshot, which is when the host says they happened.
    ///
    /// Heading takes the SHORT way around: a car turning through north must not
    /// spin the long way because 350° and 10° are far apart as numbers.
    public static func interpolated(
        from a: RaceSnapshot, to b: RaceSnapshot, alpha rawAlpha: Double
    ) -> RaceSnapshot {
        let alpha = min(1, max(0, rawAlpha))
        // alpha 1 returns `b` itself: `from + (to-from) * 1` is not bit-exact `to`
        // in float arithmetic, and the newest snapshot deserves to render exactly.
        guard alpha < 1, a.cars.count == b.cars.count else { return b }
        let cars = zip(a.cars, b.cars).map { from, to -> CarEntry in
            guard from.seat == to.seat else { return to }
            var blended = to
            blended.position = from.position + (to.position - from.position) * alpha
            blended.velocity = from.velocity + (to.velocity - from.velocity) * alpha
            blended.height = from.height + (to.height - from.height) * alpha
            blended.steerActuator =
                from.steerActuator + (to.steerActuator - from.steerActuator) * alpha
            let turn = atan2(sin(to.heading - from.heading), cos(to.heading - from.heading))
            blended.heading = from.heading + turn * alpha
            return blended
        }
        let tick = a.tick + Tick((Double(b.tick - a.tick) * alpha).rounded())
        return RaceSnapshot(tick: tick, cars: cars)
    }
}
