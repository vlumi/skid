import Foundation

/// **One lap of somebody's driving, small enough to keep forever.**
///
/// A time-trial ghost is something to race *alongside*, which is one lap. What was stored
/// instead was the whole run: on a three-lap race that is 3× more than the ghost shows,
/// and the waste grows with the lap count — which becomes a setting a player picks.
///
/// Storing a lap needs two things, and the second is why a plain slice of the inputs does
/// not work: a recording replays from a fresh `Race` at the start line, so inputs from the
/// middle of a run would be driven from the wrong place at the wrong speed. So a lap ghost
/// carries **where the car was when the lap began** as well as what the driver did.
///
/// ```text
///   whole run   [countdown][ lap 1 ][ lap 2 ][ lap 3 ]     ~1950 ticks
///   lap ghost                       ^snapshot + [ lap 2 ]   ~550 ticks
/// ```
public struct LapGhost: Equatable, Sendable, Codable {
    /// The race state at the moment the lap began — where to put the car before replaying.
    public var start: LapGhost.Start
    /// The seed the original run used. Kept because the sim consults its RNG (grid shuffle
    /// aside, anything stochastic must agree), so a replay under a different seed is a
    /// different race.
    public var seed: UInt64
    public var players: [PlayerID]
    /// One entry per tick of the lap.
    public var inputs: [[PlayerID: CarInput]]
    /// How long the lap took, so a caller can show the time without replaying it.
    public var ticks: Tick

    public init(
        start: LapGhost.Start, seed: UInt64, players: [PlayerID],
        inputs: [[PlayerID: CarInput]], ticks: Tick
    ) {
        self.start = start
        self.seed = seed
        self.players = players
        self.inputs = inputs
        self.ticks = ticks
    }

    /// Everything needed to put the cars back where the lap started.
    ///
    /// A trimmed `RaceSnapshot` rather than the whole thing: a ghost is replayed for its
    /// *line*, so the wall-contact bookkeeping and per-car progress a live sync needs are
    /// not worth storing per track. What remains is the physical state — where each car is,
    /// how fast, which way, and the actuator that shapes the next steer.
    public struct Start: Equatable, Sendable, Codable {
        public var tick: Tick
        public var cars: [CarPose]

        public init(tick: Tick, cars: [CarPose]) {
            self.tick = tick
            self.cars = cars
        }
    }

    /// One car's physical state at the start of a lap.
    public struct CarPose: Equatable, Sendable, Codable {
        public var seat: PlayerID
        public var position: Vec2
        public var velocity: Vec2
        public var heading: Double
        public var height: Double
        /// The steering actuator's position — the sim's own steering-smoothing state,
        /// non-zero on essentially every tick of a real lap.
        ///
        /// Kept because it *is* live state at the lap boundary, not because a test proves
        /// it matters: dropping it does not move the AI's line, whose inputs are smooth
        /// enough that a wheel starting straight catches up within a tick. A human's
        /// sharper inputs are the case where it would show, and that is not something the
        /// suite can drive. Cheap to store, so it is stored.
        public var steerActuator: Double

        public init(
            seat: PlayerID, position: Vec2, velocity: Vec2, heading: Double,
            height: Double, steerActuator: Double
        ) {
            self.seat = seat
            self.position = position
            self.velocity = velocity
            self.heading = heading
            self.height = height
            self.steerActuator = steerActuator
        }

        public init(seat: PlayerID, state: CarState) {
            self.init(
                seat: seat, position: state.position, velocity: state.velocity,
                heading: state.heading, height: state.height,
                steerActuator: state.steerActuator)
        }

        /// Write this pose onto a car, leaving everything else as the fresh race made it.
        public func apply(to state: inout CarState) {
            state.position = position
            state.velocity = velocity
            state.heading = heading
            state.height = height
            state.steerActuator = steerActuator
        }
    }
}

extension RaceRecording {
    /// **Cut the fastest lap out of a finished run.**
    ///
    /// Replays the recording up to the lap's first tick to learn where the cars were, then
    /// keeps that pose and the lap's inputs. Replaying is how the pose is found rather than
    /// storing one per tick: the run is deterministic, so the state at any tick is
    /// recoverable, and doing it once at save time costs nothing a player notices.
    ///
    /// Nil when the run completed no laps, or when the recording is shorter than the lap it
    /// claims — an abandoned run has nothing worth keeping.
    public func bestLapGhost(
        on track: Track, lapTimes: [Tick], config: RaceConfig, tuning: CarTuning = CarTuning()
    ) -> LapGhost? {
        guard
            let range = RaceRecording.bestLapRange(
                lapTimes: lapTimes, countdownTicks: config.countdownTicks)
        else { return nil }
        let first = Int(range.lowerBound)
        let last = Int(range.upperBound)
        // **The whole lap must be there.** Clamping to what the recording holds would
        // return a stub claiming to be a lap — a ghost that stops a third of the way round
        // and a `ticks` value that lies about the time. An abandoned run has no ghost.
        guard first < last, last <= inputs.count else { return nil }

        var race = Race(track: track, players: players, tuning: tuning, seed: seed, config: config)
        for tickInputs in inputs[..<first] {
            race.advance(inputs: tickInputs)
        }
        let start = LapGhost.Start(
            tick: race.tick,
            cars: race.cars.map { LapGhost.CarPose(seat: $0.id, state: $0.state) })
        return LapGhost(
            start: start, seed: seed, players: players,
            inputs: Array(inputs[first..<last]), ticks: Tick(last - first))
    }
}

extension Race {
    /// **Put the cars where a lap ghost's lap began**, so its inputs replay the right line.
    ///
    /// Deliberately narrower than `apply(_ snapshot:)`, which exists for live networked
    /// sync and carries progress and wall-contact bookkeeping. A ghost is replayed for its
    /// *line* only: it scores nothing, collects no gates, and is drawn rather than raced
    /// against, so seeding physical state is all it needs.
    ///
    /// Silently does nothing when the seats do not line up — a ghost recorded with a
    /// different field is not this race's ghost, and refusing is better than putting one
    /// car's pose onto another's.
    public mutating func seed(from start: LapGhost.Start) {
        guard start.cars.count == cars.count,
            zip(cars, start.cars).allSatisfy({ $0.id == $1.seat })
        else { return }
        tick = start.tick
        for (index, pose) in start.cars.enumerated() {
            pose.apply(to: &cars[index].state)
        }
    }
}
