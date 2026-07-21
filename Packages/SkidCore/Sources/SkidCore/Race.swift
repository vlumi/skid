import Foundation

/// The whole deterministic simulation: same inputs → same states,
/// bit-for-bit. Advances at a fixed timestep; no I/O, no rendering, no
/// wall-clock time anywhere.
public struct Race: Equatable, Sendable {
    /// Simulation rate. The step is exactly `1 / tickRate` seconds.
    public static let tickRate = 60
    public static let dt = 1.0 / Double(tickRate)

    public let track: Track
    public var tuning: CarTuning
    public private(set) var tick: Tick
    public private(set) var cars: [Car]
    /// Seeded, injected randomness — unused by the core physics, but any
    /// future random effect must draw from here to stay reproducible.
    public private(set) var rng: SeededRNG

    public init(
        track: Track, players: [PlayerID], tuning: CarTuning = CarTuning(), seed: UInt64 = 0
    ) {
        self.track = track
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

    /// Advance one tick. Missing inputs coast.
    public mutating func advance(inputs: [PlayerID: CarInput]) {
        for i in cars.indices {
            var state = cars[i].state
            step(car: &state, input: inputs[cars[i].id] ?? .coast)
            cars[i].state = state
        }
        tick += 1
    }

    private func step(car: inout CarState, input: CarInput) {
        let dt = Race.dt
        let surface = track.surface(at: car.position, layer: car.layer)

        // Steering: yaw follows steer, scaled up to full effect at
        // steerFullSpeed; reversing mirrors the wheel like a real car.
        let speedAlongHeading = car.velocity.dot(car.forward)
        let effectiveness = min(1, abs(speedAlongHeading) / tuning.steerFullSpeed)
        let direction: Double = speedAlongHeading < 0 ? -1 : 1
        car.heading += input.steer * tuning.turnRate * effectiveness * direction * dt

        // Decompose the world-space velocity against the NEW heading: the
        // nose turned away from the momentum, so part of it is now lateral —
        // that lateral remainder IS the drift.
        let fwd = car.forward
        var forwardSpeed = car.velocity.dot(fwd)
        var lateral = car.velocity - fwd * forwardSpeed

        // Engine/brake along the heading, limited by surface traction.
        let accel = input.throttle >= 0 ? tuning.engineAccel : tuning.brakeAccel
        forwardSpeed += input.throttle * accel * surface.traction * dt
        forwardSpeed = max(-tuning.reverseMaxSpeed, min(tuning.maxSpeed, forwardSpeed))

        // Grip bleeds the slide, but never all of it in one tick — what
        // remains carries the car wide through the corner.
        lateral *= max(0, 1 - surface.grip * dt)
        forwardSpeed *= max(0, 1 - surface.drag * dt)

        car.velocity = fwd * forwardSpeed + lateral
        car.position += car.velocity * dt

        collideWithWalls(car: &car)
    }

    private func collideWithWalls(car: inout CarState) {
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
            }
        }
    }
}
