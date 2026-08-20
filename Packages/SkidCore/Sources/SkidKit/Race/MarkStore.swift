import SkidCore
import SwiftUI

/// Accumulated tire marks for the current run, pre-batched for cheap
/// rendering: segments are appended into a small set of `Path`s (one visual
/// bucket × fixed-size chunks), so drawing is a few dozen stroke calls
/// however many marks exist — per-segment strokes made the game choppy on
/// device once marks piled up. Oldest chunk drops first, so marks fade by
/// age. Pure rendering state, derived from sim ticks — never fed back into
/// physics.
public struct MarkStore {
    /// The visual style a segment is baked into.
    public enum Bucket: CaseIterable {
        case rubberLight  // moderate slide on asphalt
        case rubberHeavy  // hard slide on asphalt
        case scuff  // torn into grass/mud off the ribbon
        case mudTrail  // mud carried back onto the asphalt
        case wetTrail  // water carried back onto the asphalt
    }

    /// Up to `chunkSegments` mark segments baked into one path.
    public struct Chunk {
        public var path = Path()
        public var count = 0
    }

    /// The marks, banked BY STOREY — each storey's rubber draws in that
    /// storey's own render band, after its road and before the next band's.
    /// This used to be two banks (ground and "elevated"), and every elevated
    /// band re-drew the one elevated bank: on a three-storey track, rubber
    /// laid on the first deck was painted again on top of the bridges crossing
    /// above it (reported from device as tire tracks from below the bridge
    /// visible on the bridge and its railing).
    public private(set) var chunks: [Int: [Bucket: [Chunk]]] = [:]

    private var lastTirePositions: [PlayerID: [Vec2]] = [:]
    /// Mud/water clinging to a car's tires: what it drove through and for
    /// how many more recorded ticks it keeps printing onto the asphalt.
    private var carryover: [PlayerID: (bucket: Bucket, remaining: Int)] = [:]

    /// Marks record at half the sim rate — visually indistinguishable at
    /// speed, halves both memory and stroke load.
    static let recordEvery: Tick = 2
    static let chunkSegments = 256
    /// Per-bucket chunk cap: 3 × 12 × 256 ≈ 9k segments worst case, drawn
    /// in ≤36 strokes.
    static let maxChunksPerBucket = 12
    /// Skip segments shorter than this — crawling produces dust, not marks.
    private static let minSegmentLengthSquared = 4.0
    /// Slip speed (units/s) where rubber starts burning on asphalt.
    static let rubberSlipThreshold: Double = 90
    /// Slip beyond this burns the heavy bucket.
    static let heavyRubberSlip: Double = 190
    /// Ground speed where off-road driving starts scuffing.
    static let scuffSpeedThreshold: Double = 50
    /// Recorded ticks of mud/water tire prints after leaving the hazard.
    static let carryoverTicks = 50

    public init() {}

    public mutating func reset() {
        chunks.removeAll()
        lastTirePositions.removeAll()
        carryover.removeAll()
    }

    /// Record marks for one car after a sim tick. Rubber comes off the rear
    /// pair in a slide; scuffs come off all four when off the asphalt.
    public mutating func record(car: Car, on track: Track, tick: Tick) {
        guard tick % Self.recordEvery == 0 else { return }
        let state = car.state
        // Mid-air prints nothing; everything else marks its own level — a
        // storey's bucket draws after that storey's ribbon, so deck rubber shows.
        guard !state.isAirborne else {
            lastTirePositions[car.id] = nil
            return
        }
        let tires = state.tirePositions
        defer { lastTirePositions[car.id] = tires }
        guard let previous = lastTirePositions[car.id], previous.count == tires.count else {
            return
        }

        // **A mark belongs to the storey its road PAINTS at, not to the car's raw
        // height** — the same rule that stacks the cars (`carStorey`), for the same
        // reason: a ramp's ribbon paints whole at the level of its highest end, so a
        // mark laid on the ramp's low beginning (where the car is still at ground
        // height) went into the ground bank and the ramp's own asphalt painted over
        // it. Reported from device: tire marks stop dead at the beginning of a ramp.
        //
        // Computed AFTER the guard above: it is five centerline queries (the car's
        // centre plus its corners), and on the first recorded tick of a car — and
        // every tick after a spell airborne — there is no previous tire set to draw
        // from, so the answer was thrown away.
        let storey = TrackRenderer.carStorey(of: state, on: track)
        let surface = track.surface(at: state.position, height: state.height)
        let slip = state.slipSpeed
        let speed = state.velocity.length

        // Driving through mud/water loads the tires; they print it back
        // onto the asphalt for a while — the classic look.
        switch surface {
        case .mud: carryover[car.id] = (.mudTrail, Self.carryoverTicks)
        case .water: carryover[car.id] = (.wetTrail, Self.carryoverTicks)
        default: break
        }

        let bucket: Bucket
        let tireRange: Range<Int>
        if surface == .asphalt, slip > Self.rubberSlipThreshold {
            bucket = slip > Self.heavyRubberSlip ? .rubberHeavy : .rubberLight
            tireRange = 0..<2  // rear pair
        } else if surface == .asphalt, let carried = carryover[car.id], carried.remaining > 0,
            speed > Self.scuffSpeedThreshold
        {
            bucket = carried.bucket
            tireRange = 0..<4
            carryover[car.id] =
                carried.remaining > 1 ? (carried.bucket, carried.remaining - 1) : nil
        } else if surface != .asphalt, surface != .oil, speed > Self.scuffSpeedThreshold {
            bucket = .scuff
            tireRange = 0..<4
        } else {
            return
        }

        for i in tireRange {
            append(from: previous[i], to: tires[i], in: bucket, storey: storey)
        }
    }

    private mutating func append(from a: Vec2, to b: Vec2, in bucket: Bucket, storey: Int) {
        guard (b - a).lengthSquared >= Self.minSegmentLengthSquared else { return }
        var list = chunks[storey]?[bucket] ?? []
        if list.isEmpty || list[list.count - 1].count >= Self.chunkSegments {
            list.append(Chunk())
            if list.count > Self.maxChunksPerBucket {
                list.removeFirst()
            }
        }
        list[list.count - 1].path.move(to: CGPoint(x: a.x, y: a.y))
        list[list.count - 1].path.addLine(to: CGPoint(x: b.x, y: b.y))
        list[list.count - 1].count += 1
        chunks[storey, default: [:]][bucket] = list
    }
}
