import Foundation

/// How a run is structured. Defaults make a free practice session (no
/// countdown, no finish); a real race sets both.
public struct RaceConfig: Equatable, Sendable, Codable {
    /// Laps to the flag; nil = free practice, drive forever.
    public var laps: Int?
    /// Ticks of start countdown, during which cars are held on the grid.
    public var countdownTicks: Int
    /// Car contact is a race option, not a constant: `true` = cars collide
    /// and bump (derby flavour); `false` = ghost racing, cars pass through
    /// each other (pure speed). Walls and surfaces behave the same in both.
    public var carContact: Bool

    public init(laps: Int? = nil, countdownTicks: Int = 0, carContact: Bool = true) {
        self.laps = laps
        self.countdownTicks = countdownTicks
        self.carContact = carContact
    }
}

/// One car's progress through the gate sequence. A lap is earned by
/// crossing every gate in order, in the driving direction — cutting the
/// track can never skip ahead.
public struct CarProgress: Equatable, Sendable, Codable {
    /// Index into `track.gates` of the next gate that counts.
    public var nextGate = 0
    /// Completed laps.
    public var lap = 0
    /// Tick the current lap started at.
    public var lapStartTick: Tick = 0
    /// Completed lap durations, in ticks.
    public var lapTimes: [Tick] = []
    /// Tick the car took the flag, once it has.
    public var finishedAt: Tick?

    public init() {}

    public var bestLapTicks: Tick? { lapTimes.min() }
}

/// One car in the race: identity + dynamic state + race progress.
public struct Car: Equatable, Sendable, Codable {
    public let id: PlayerID
    public var state: CarState
    public var progress = CarProgress()

    public init(id: PlayerID, state: CarState) {
        self.id = id
        self.state = state
    }
}

/// Something audible/tactile that happened during a tick — derived
/// deterministically from the sim, consumed by sound/haptics. Never fed
/// back into physics.
public enum RaceEvent: Equatable, Sendable {
    case wallImpact(PlayerID, speed: Double)
    case carImpact(PlayerID, PlayerID, closingSpeed: Double)
    case lapCompleted(PlayerID, lapTicks: Tick)
    case finished(PlayerID)
}

/// The whole deterministic simulation: same inputs → same states,
/// bit-for-bit. Advances at a fixed timestep; no I/O, no rendering, no
/// wall-clock time anywhere.
public struct Race: Equatable, Sendable {
    /// Simulation rate. The step is exactly `1 / tickRate` seconds.
    public static let tickRate = 60
    public static let dt = 1.0 / Double(tickRate)

    public enum Phase: Equatable, Sendable {
        case countdown(remainingTicks: Int)
        case running
        case finished
    }

    public let track: Track
    public let config: RaceConfig
    public var tuning: CarTuning
    /// Setter internal for exactly one caller: `apply(_ snapshot:)`, which is how a
    /// client of a host-authoritative race adopts the host's state. Nothing else may
    /// write it — the sim advances it, a snapshot overwrites it, and those two never
    /// happen to the same instance.
    public internal(set) var tick: Tick
    /// Setter internal so tests can stage scenarios (@testable).
    public internal(set) var cars: [Car]
    /// Seeded, injected randomness — unused by the core physics, but any
    /// future random effect must draw from here to stay reproducible.
    public private(set) var rng: SeededRNG
    /// What happened during the most recent `advance` — impacts, laps,
    /// finishes. Deterministic like everything else.
    public private(set) var lastEvents: [RaceEvent] = []

    public init(
        track: Track, players: [PlayerID], tuning: CarTuning = CarTuning(), seed: UInt64 = 0,
        config: RaceConfig = RaceConfig()
    ) {
        self.track = track
        self.config = config
        self.tuning = tuning
        self.tick = 0
        var rng = SeededRNG(seed: seed)
        // Randomise the grid every race: shuffle which player takes which
        // start slot, driven by the seeded RNG so replays and ghosts stay
        // exact. Slot geometry (positions + heading) is untouched — only the
        // player→slot assignment varies.
        let order = Array(players.indices).shuffled(using: &rng)
        self.rng = rng
        self.cars = players.enumerated().map { index, id in
            let slotIndex = order[index]
            let slot =
                slotIndex < track.startSlots.count
                ? track.startSlots[slotIndex] : track.startSlots.last ?? Vec2.zero
            return Car(
                id: id,
                state: CarState(
                    position: slot, heading: track.startHeading, height: track.startHeight))
        }
    }

    public var phase: Phase {
        if tick < config.countdownTicks {
            return .countdown(remainingTicks: config.countdownTicks - tick)
        }
        if config.laps != nil, !cars.isEmpty, cars.allSatisfy({ $0.progress.finishedAt != nil }) {
            return .finished
        }
        return .running
    }

    /// Ticks of racing so far (excludes the countdown).
    public var raceTicks: Tick { max(0, tick - config.countdownTicks) }

    /// Advance one tick. Missing inputs coast; cars held in the countdown
    /// and rolling out after their flag always coast.
    ///
    /// **Every input is quantised on the way in**, to the same four bytes the wire and a
    /// recording use — which is what makes both storable. A peer sending quantised input
    /// while stepping its own raw thumb value diverges slowly and looks like a physics bug;
    /// a recording stored as four bytes a tick replays a different line (measured: a clover
    /// ghost diverged at **tick 0** before this, and is bit-identical with it). The
    /// precision lost is far below what a thumb can express, and lost *uniformly*, which is
    /// the property that matters.
    public mutating func advance(inputs rawInputs: [PlayerID: CarInput]) {
        let inputs = rawInputs.mapValues(\.quantised)
        let held = tick < config.countdownTicks
        if tick == config.countdownTicks {
            // First running tick: lap timing starts now, for everyone.
            for i in cars.indices {
                cars[i].progress.lapStartTick = tick
            }
        }
        lastEvents.removeAll()
        var origins = [Vec2](repeating: .zero, count: cars.count)
        for i in cars.indices {
            var car = cars[i]
            origins[i] = car.state.position
            let locked = held || car.progress.finishedAt != nil
            var state = car.state
            let wallImpact = step(car: &state, input: locked ? .coast : (inputs[car.id] ?? .coast))
            car.state = state
            if wallImpact > 60 {
                lastEvents.append(.wallImpact(car.id, speed: wallImpact))
            }
            cars[i] = car
        }
        if config.carContact, !held {
            collideCars()
        }
        if !held {
            for i in cars.indices {
                var car = cars[i]
                applyRamps(car: &car, movedFrom: origins[i])
                let lapsBefore = car.progress.lapTimes.count
                let finishedBefore = car.progress.finishedAt != nil
                updateProgress(car: &car, movedFrom: origins[i])
                if car.progress.lapTimes.count > lapsBefore,
                    let lap = car.progress.lapTimes.last
                {
                    lastEvents.append(.lapCompleted(car.id, lapTicks: lap))
                }
                if !finishedBefore, car.progress.finishedAt != nil {
                    lastEvents.append(.finished(car.id))
                }
                cars[i] = car
            }
        }
        tick += 1
    }

    /// **The car follows the height of the road it is on.**
    ///
    /// This replaced a layer state machine that flipped the car between discrete
    /// levels whenever it crossed a ramp's transition line. Every bridge bug came
    /// from that design: the car popped as it flipped, the road vanished from
    /// under it mid-transition, and — worst — a car driving *under* a bridge could
    /// come out on top of the ramp, because a transition line has no way to know
    /// which of two overlapping roads you are on.
    ///
    /// Reading the height off the nearest road *at the car's current height*
    /// makes all of that unreachable. The car under the bridge is at 0, matches
    /// the road at 0, and stays there; nothing can lift it. Climbing a ramp, the
    /// nearest road at ~its height is the next bit of slope, so it rises
    /// smoothly. The only discontinuity left is a genuine one: driving off the
    /// deck's edge, which is a fall.
    ///
    /// A launch line still throws the car, since that IS an event at a place.
    private func applyRamps(car: inout Car, movedFrom from: Vec2) {
        guard !car.state.isAirborne else { return }

        // **Only the road the car is physically standing on may carry it** — the
        // nearest road AT the car's own height, within the real asphalt
        // half-width, no margin. Off-road the car keeps the height it has.
        //
        // Asking "is there road near my height?" instead is what let a car on the
        // grass beside a ramp be judged on-road: 60 units from the ground road but
        // 47 from the ramp, inside the old margin, so it took the ramp's height and
        // arrived on the bridge without driving up anything.
        //
        // Judged at BOTH ends of the tick's movement, because the car moves before
        // this runs: testing only where it arrived let it cross from grass onto
        // ramp asphalt within one tick and inherit the slope (20 of 520 runs
        // reached the deck).
        let height = car.state.height
        func onOwnRoad(_ position: Vec2) -> Bool {
            track.distanceToCenterline(position, height: height)
                <= track.halfWidth(atHeight: height)
        }
        guard onOwnRoad(car.state.position), onOwnRoad(from) else {
            // Off the road. Up high, that's a fall off the deck; on the ground,
            // it's just grass.
            // Falling off the deck drops to the GROUND, which is a real floor
            // regardless of where the track's grid sits.
            if car.state.height > Track.heightEpsilon {
                // Fall from where the car actually is, rather than snapping to
                // the ground and then flying — which put it at the bottom
                // before it visually landed.
                //
                // `applyRamps` runs AFTER `step`, so the tick that notices the
                // car left the road has already moved it as if grounded. Take
                // this tick's descent here, or the fall visibly starts late.
                car.state.airborneTicks = 1
                car.state.verticalSpeed -= tuning.gravity * Race.dt
                car.state.height += car.state.verticalSpeed * Race.dt
            }
            return
        }
        // On the road: take its height, anchored to the height the car already
        // had so a bridge crossing can't swap it to the other road. Clamped to a
        // per-tick step so even a badly-formed track can only ramp the car
        // smoothly, never teleport it between levels.
        let target = track.height(at: car.state.position, preferHeight: car.state.height)
        let step = Self.maxHeightChangePerTick
        car.state.height += max(-step, min(step, target - car.state.height))
    }

    /// **What a falling car lands on**: the road beneath it, or the ground.
    ///
    /// `preferHeight` is the height the car is falling THROUGH, so the resolver
    /// picks the road nearest below rather than the one it just left — that is
    /// what lets a fall from the top storey settle on a deck instead of dropping
    /// through it. Off the road entirely, the ground is the floor.
    private func landingHeight(under position: Vec2, fallingFrom height: Double) -> Double {
        let road = track.height(at: position, preferHeight: height)
        guard road <= height + Track.reachTolerance,
            track.distanceToCenterline(position, height: road)
                <= track.halfWidth(atHeight: road)
        else { return 0 }
        return road
    }

    /// The most the car's height can change in one tick. A ramp climbs over many
    /// ticks, so this never limits legitimate driving; it exists so that no track,
    /// however odd, can snap a car between the ground and a deck.
    static let maxHeightChangePerTick = 0.08

    /// Car–car contact: equal-mass circles push apart and exchange the
    /// closing velocity component with restitution. Pairs resolve in index
    /// order — deterministic like everything else.
    private mutating func collideCars() {
        guard cars.count > 1 else { return }
        for i in 0..<(cars.count - 1) {
            for j in (i + 1)..<cars.count {
                // Cars only touch if they're at the same height: one on the
                // bridge and one underneath must pass cleanly.
                guard
                    abs(cars[i].state.height - cars[j].state.height)
                        <= Track.reachTolerance,
                    !cars[i].state.isAirborne, !cars[j].state.isAirborne
                else { continue }
                let offset = cars[j].state.position - cars[i].state.position
                let dist = offset.length
                let minDist = CarGeometry.radius * 2
                guard dist < minDist, dist > 0 else { continue }
                let normal = offset.normalized
                let push = normal * ((minDist - dist) / 2)
                cars[i].state.position -= push
                cars[j].state.position += push
                let closing = (cars[j].state.velocity - cars[i].state.velocity).dot(normal)
                if closing < 0 {
                    let impulse = normal * (-(1 + tuning.carRestitution) * closing / 2)
                    cars[i].state.velocity -= impulse
                    cars[j].state.velocity += impulse
                    if -closing > 70 {
                        lastEvents.append(
                            .carImpact(cars[i].id, cars[j].id, closingSpeed: -closing))
                    }
                }
            }
        }
    }

    private func updateProgress(car: inout Car, movedFrom from: Vec2) {
        guard car.progress.finishedAt == nil, !track.gates.isEmpty else { return }
        let gate = track.gates[car.progress.nextGate]
        guard abs(gate.height - car.state.height) <= Track.reachTolerance,
            gate.crossedForward(movingFrom: from, to: car.state.position)
        else { return }
        car.progress.nextGate += 1
        guard car.progress.nextGate == track.gates.count else { return }
        // Crossed the start/finish with every gate collected: lap earned.
        car.progress.nextGate = 0
        car.progress.lap += 1
        car.progress.lapTimes.append(tick - car.progress.lapStartTick)
        car.progress.lapStartTick = tick
        if let laps = config.laps, car.progress.lap >= laps {
            car.progress.finishedAt = tick
        }
    }

    /// Returns the hardest wall impact this tick (0 if none).
    @discardableResult
    private func step(car: inout CarState, input: CarInput) -> Double {
        let dt = Race.dt
        if car.isAirborne {
            // Ballistic: no steering, no throttle, no grip, no drag. Horizontal
            // velocity is carried unchanged; only height is acted on.
            car.verticalSpeed -= tuning.gravity * dt
            car.height += car.verticalSpeed * dt
            let before = car.position
            car.position += car.velocity * dt
            // **Flight ends by meeting a surface, not by a timer.** The ground
            // the car came down onto is whatever is under it — so a fall from
            // the top storey lands on a deck below rather than through it.
            let floor = landingHeight(under: car.position, fallingFrom: car.height)
            if car.verticalSpeed <= 0, car.height <= floor {
                car.height = floor
                car.verticalSpeed = 0
                car.airborneTicks = 0
            } else {
                // Kept only so `isAirborne` stays true and the counter remains
                // readable in the debug overlay; the arc decides when to land.
                car.airborneTicks = min(600, car.airborneTicks + 1)
            }
            return collideWithWalls(car: &car, movedFrom: before)
        }
        let surface = track.surface(at: car.position, height: car.height)
        turn(car: &car, input: input, dt: dt)

        // Decompose the world-space velocity against the NEW heading: the
        // nose turned away from the momentum, so part of it is now lateral —
        // that lateral remainder IS the drift.
        let fwd = car.forward
        var forwardSpeed = car.velocity.dot(fwd)
        var lateral = car.velocity - fwd * forwardSpeed

        // Engine/brake along the heading, limited by surface traction.
        let accel = input.throttle >= 0 ? tuning.engineAccel : tuning.brakeAccel
        forwardSpeed += input.throttle * accel * surface.traction * dt

        // Grip bleeds the slide, but never all of it in one tick — what
        // remains carries the car wide through the corner. The speed the
        // bleed takes OUT of the slide is redirected along the nose
        // (driftRetention, energy-true: at 1 a drift redirects momentum
        // without scrubbing it, and never manufactures any) — the arcade
        // rule that makes flicking the body into a corner carry its speed.
        let kept = lateral * max(0, 1 - surface.grip * tuning.gripScale * dt)
        let redirected = tuning.driftRetention * (lateral.lengthSquared - kept.lengthSquared)
        if redirected > 0 {
            let sense: Double = forwardSpeed < 0 ? -1 : 1
            forwardSpeed = sense * (forwardSpeed * forwardSpeed + redirected).squareRoot()
        }
        lateral = kept

        forwardSpeed = max(-tuning.reverseMaxSpeed, min(tuning.maxSpeed, forwardSpeed))
        forwardSpeed *= max(0, 1 - surface.drag * dt)

        car.velocity = fwd * forwardSpeed + lateral
        // Top speed caps the WHOLE velocity, not just the nose component —
        // otherwise a held drift (slip + full throttle) creeps past the cap.
        // A drift carries full speed; it never beats it.
        let speed = car.velocity.length
        if speed > tuning.maxSpeed {
            car.velocity *= tuning.maxSpeed / speed
        }
        let beforeMove = car.position
        car.position += car.velocity * dt

        return collideWithWalls(car: &car, movedFrom: beforeMove)
    }

    /// One tick of heading change: either the wheel (steer channel) or the
    /// body-flip (aim channel).
    private func turn(car: inout CarState, input: CarInput, dt: Double) {
        let speedAlongHeading = car.velocity.dot(car.forward)
        let effectiveness = min(1, abs(speedAlongHeading) / tuning.steerFullSpeed)
        let maxStep = tuning.steerRate * dt

        // The body-flip's speed scaling, CURVED (squared): near-nothing at
        // low speed so slow maneuvering stays gentle, unchanged flat-out.
        // Both the aim and steer flips share it. A linear ramp gave too much
        // flip while crawling.
        let flipScale = pow(min(1, car.velocity.length / tuning.maxSpeed), 2)

        if let aim = input.aim {
            // The body chases the pointed heading directly — the flip. Base
            // rate needs rolling speed (a parked car can't spin in place);
            // the boost grows with speed like a handbrake's inertia: fast
            // cars wrench around almost instantly, slow ones ease over.
            car.steerActuator += max(-maxStep, min(maxStep, -car.steerActuator))
            let error = atan2(sin(aim - car.heading), cos(aim - car.heading))
            let yawRate = tuning.aimTurnRate * effectiveness + tuning.aimFlipBoost * flipScale
            let maxYaw = yawRate * dt
            car.heading += max(-maxYaw, min(maxYaw, error))
            return
        }

        // The wheel chases the thumb at a bounded rate instead of matching
        // it instantly — a twitch no longer snaps the nose, but full lock is
        // still reached in ~1/steerRate s. Yaw follows the actuator, scaled
        // up to full effect at steerFullSpeed; reversing mirrors the wheel
        // like a real car.
        let delta = input.steer - car.steerActuator
        car.steerActuator += max(-maxStep, min(maxStep, delta))
        let direction: Double = speedAlongHeading < 0 ? -1 : 1
        car.heading += car.steerActuator * tuning.turnRate * effectiveness * direction * dt

        // Flip assist: at speed, holding a direction rotates the body toward
        // it beyond the wheel — so the drift model carries you into a slide
        // without countersteer (what makes the d-pad, and the digital
        // keyboard that reuses it, drift). Scales with speed (parking stays
        // a plain wheel) and the analog steer amount (a light thumb still
        // places the car precisely).
        car.heading += car.steerActuator * tuning.steerFlipBoost * flipScale * direction * dt
    }
}
