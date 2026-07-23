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
    public private(set) var tick: Tick
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
        self.rng = SeededRNG(seed: seed)
        self.cars = players.enumerated().map { index, id in
            let slot =
                index < track.startSlots.count
                ? track.startSlots[index] : track.startSlots.last ?? Vec2.zero
            return Car(id: id, state: CarState(position: slot, heading: track.startHeading))
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
    public mutating func advance(inputs: [PlayerID: CarInput]) {
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

    /// Ramp lines switch layers; launching ramps also throw the car into a
    /// brief ballistic flight scaled by its speed. Driving back through a
    /// ramp backward takes the car down again. A grounded elevated car
    /// that strays off its ribbon falls back to the ground layer.
    private func applyRamps(car: inout Car, movedFrom from: Vec2) {
        guard !car.state.isAirborne else { return }
        var flippedThisTick = false
        for ramp in track.ramps {
            switch ramp.crossing(movingFrom: from, to: car.state.position) {
            case 1 where car.state.layer == ramp.fromLayer:
                car.state.layer = ramp.toLayer
                flippedThisTick = true
                if ramp.launches {
                    let flight = Int(car.state.velocity.length * tuning.jumpTicksPerSpeed)
                    car.state.airborneTicks = min(60, flight)
                }
            case -1 where car.state.layer == ramp.toLayer:
                car.state.layer = ramp.fromLayer
                flippedThisTick = true
            default:
                break
            }
        }
        // Never fall off on the very tick a ramp flipped the layer — the
        // car is at the deck's edge by definition there.
        if !flippedThisTick, car.state.layer > 0,
            track.distanceToCenterline(car.state.position, layer: car.state.layer)
                > track.width / 2 + 6
        {
            // Off the edge of the bridge: a short drop back to the ground.
            car.state.layer = 0
            car.state.airborneTicks = 8
        }
    }

    /// Car–car contact: equal-mass circles push apart and exchange the
    /// closing velocity component with restitution. Pairs resolve in index
    /// order — deterministic like everything else.
    private mutating func collideCars() {
        guard cars.count > 1 else { return }
        for i in 0..<(cars.count - 1) {
            for j in (i + 1)..<cars.count {
                guard cars[i].state.layer == cars[j].state.layer,
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
        guard gate.layer == car.state.layer,
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
            // Ballistic: no steering, no throttle, no grip, no drag — the
            // car flies straight until it lands.
            car.airborneTicks -= 1
            car.position += car.velocity * dt
            return collideWithWalls(car: &car)
        }
        let surface = track.surface(at: car.position, layer: car.layer)
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
        car.position += car.velocity * dt

        return collideWithWalls(car: &car)
    }

    /// One tick of heading change: either the wheel (steer channel) or the
    /// body-flip (aim channel).
    private func turn(car: inout CarState, input: CarInput, dt: Double) {
        let speedAlongHeading = car.velocity.dot(car.forward)
        let effectiveness = min(1, abs(speedAlongHeading) / tuning.steerFullSpeed)
        let maxStep = tuning.steerRate * dt

        // The body-flip's speed scaling, CURVED (squared): near-nothing at
        // low speed so slow manoeuvring stays gentle, unchanged flat-out.
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

    /// Returns the hardest into-wall speed absorbed (0 if no contact).
    private func collideWithWalls(car: inout CarState) -> Double {
        var hardest = 0.0
        for wall in track.walls where wall.layer == car.layer {
            let closest = car.position.closestPoint(onSegment: wall.a, wall.b)
            let offset = car.position - closest
            let dist = offset.length
            guard dist < CarGeometry.radius, dist > 0 else { continue }
            let normal = offset.normalized
            // Push out of the wall, then reflect the into-wall velocity
            // component with restitution.
            car.position = closest + normal * CarGeometry.radius
            let intoWall = car.velocity.dot(normal)
            if intoWall < 0 {
                car.velocity -= normal * intoWall * (1 + tuning.wallRestitution)
                hardest = max(hardest, -intoWall)
            }
        }
        return hardest
    }
}
