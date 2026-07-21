import Foundation
import SkidCore

/// One dab of tire mark on the ground: a short segment between a tire's
/// position on consecutive ticks.
public struct MarkSegment {
    public enum Kind {
        case rubber  // burnt onto asphalt in a hard slide
        case scuff  // torn into grass/mud off the ribbon
    }

    public var a: Vec2
    public var b: Vec2
    public var kind: Kind
    /// 0…1, scales rendered opacity with how hard the slide was.
    public var intensity: Double
}

/// Accumulated marks for the current run. Pure rendering state, derived from
/// sim ticks — never fed back into physics. Capped so a long session can't
/// grow unbounded.
public struct MarkStore {
    public private(set) var segments: [MarkSegment] = []
    private var lastTirePositions: [PlayerID: [Vec2]] = [:]

    static let capacity = 24_000
    /// Slip speed (units/s) where rubber starts burning on asphalt.
    static let rubberSlipThreshold: Double = 90
    /// Ground speed where off-road driving starts scuffing.
    static let scuffSpeedThreshold: Double = 50

    public init() {}

    public mutating func reset() {
        segments.removeAll()
        lastTirePositions.removeAll()
    }

    /// Record marks for one car after a sim tick. Rubber comes off the rear
    /// pair in a slide; scuffs come off all four when off the asphalt.
    public mutating func record(car: Car, on track: Track) {
        let state = car.state
        let tires = state.tirePositions
        defer { lastTirePositions[car.id] = tires }
        guard let previous = lastTirePositions[car.id], previous.count == tires.count else {
            return
        }

        let surface = track.surface(at: state.position, layer: state.layer)
        let slip = state.slipSpeed
        let speed = state.velocity.length

        let kind: MarkSegment.Kind
        let tireRange: Range<Int>
        let intensity: Double
        if surface == .asphalt, slip > Self.rubberSlipThreshold {
            kind = .rubber
            tireRange = 0..<2  // rear pair
            intensity = min(1, (slip - Self.rubberSlipThreshold) / 150)
        } else if surface != .asphalt, surface != .oil, speed > Self.scuffSpeedThreshold {
            kind = .scuff
            tireRange = 0..<4
            intensity = min(1, speed / 400)
        } else {
            return
        }

        for i in tireRange {
            segments.append(
                MarkSegment(a: previous[i], b: tires[i], kind: kind, intensity: intensity))
        }
        if segments.count > Self.capacity {
            segments.removeFirst(segments.count - Self.capacity + Self.capacity / 8)
        }
    }
}
