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

    public private(set) var chunks: [Bucket: [Chunk]] = [:]

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
        // Marks live on the ground layer only: nothing prints from the
        // bridge (it would draw under it) or from mid-air.
        guard state.layer == 0, !state.isAirborne else {
            lastTirePositions[car.id] = nil
            return
        }
        let tires = state.tirePositions
        defer { lastTirePositions[car.id] = tires }
        guard let previous = lastTirePositions[car.id], previous.count == tires.count else {
            return
        }

        let surface = track.surface(at: state.position, layer: state.layer)
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
            append(from: previous[i], to: tires[i], in: bucket)
        }
    }

    private mutating func append(from a: Vec2, to b: Vec2, in bucket: Bucket) {
        guard (b - a).lengthSquared >= Self.minSegmentLengthSquared else { return }
        var list = chunks[bucket] ?? []
        if list.isEmpty || list[list.count - 1].count >= Self.chunkSegments {
            list.append(Chunk())
            if list.count > Self.maxChunksPerBucket {
                list.removeFirst()
            }
        }
        list[list.count - 1].path.move(to: CGPoint(x: a.x, y: a.y))
        list[list.count - 1].path.addLine(to: CGPoint(x: b.x, y: b.y))
        list[list.count - 1].count += 1
        chunks[bucket] = list
    }
}
