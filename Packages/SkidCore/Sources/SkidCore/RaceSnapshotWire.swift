import Foundation

/// `RaceSnapshot` as bytes — hand-rolled like `LockstepClock.Packet`, because
/// `Codable` is not a wire format (measured there: 15× inflation from spelling
/// keys per entry). `Float32` throughout: the client renders these numbers, it
/// never simulates with them, so display precision is the right precision.
extension RaceSnapshot {
    public var encoded: [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(5 + cars.count * 48)
        out.appendInt32(Int32(tick))
        out.append(UInt8(truncatingIfNeeded: cars.count))
        for car in cars {
            out.append(UInt8(truncatingIfNeeded: car.seat.rawValue))
            out.append(car.airborne ? 1 : 0)
            out.appendFloat(car.position.x)
            out.appendFloat(car.position.y)
            out.appendFloat(car.velocity.x)
            out.appendFloat(car.velocity.y)
            out.appendFloat(car.heading)
            out.appendFloat(car.height)
            out.appendFloat(car.steerActuator)
            out.append(UInt8(truncatingIfNeeded: car.progress.nextGate))
            out.append(UInt8(truncatingIfNeeded: car.progress.lap))
            out.appendInt32(Int32(car.progress.lapStartTick))
            out.appendInt32(Int32(car.progress.finishedAt ?? -1))
            out.append(UInt8(truncatingIfNeeded: car.progress.lapTimes.count))
            for lap in car.progress.lapTimes { out.appendInt32(Int32(lap)) }
        }
        return out
    }

    /// Nil on ANY malformation — this parses data off the network, and a clipped
    /// datagram must be dropped, never partially believed.
    public init?(bytes: [UInt8]) {
        var reader = ByteReader(bytes)
        guard let tick = reader.int32(), let count = reader.byte() else { return nil }
        var cars: [CarEntry] = []
        cars.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let car = RaceSnapshot.readCar(&reader) else { return nil }
            cars.append(car)
        }
        guard reader.isDrained else { return nil }  // trailing garbage is malformed too
        self.init(tick: Tick(tick), cars: cars)
    }

    private static func readCar(_ reader: inout ByteReader) -> CarEntry? {
        guard let seat = reader.byte(), let flags = reader.byte(),
            let px = reader.float(), let py = reader.float(),
            let vx = reader.float(), let vy = reader.float(),
            let heading = reader.float(), let height = reader.float(),
            let actuator = reader.float(),
            let nextGate = reader.byte(), let lap = reader.byte(),
            let lapStart = reader.int32(), let finishedAt = reader.int32(),
            let lapCount = reader.byte()
        else { return nil }
        var progress = CarProgress()
        progress.nextGate = Int(nextGate)
        progress.lap = Int(lap)
        progress.lapStartTick = Tick(lapStart)
        progress.finishedAt = finishedAt < 0 ? nil : Tick(finishedAt)
        for _ in 0..<lapCount {
            guard let lapTime = reader.int32() else { return nil }
            progress.lapTimes.append(Tick(lapTime))
        }
        return CarEntry(
            seat: PlayerID(Int(seat)), position: Vec2(px, py), velocity: Vec2(vx, vy),
            heading: heading, height: height, steerActuator: actuator,
            airborne: flags & 1 == 1, progress: progress)
    }
}

/// Sequential little-endian reads with bounds checks, so a malformed packet is a
/// nil instead of a trap. The packet-decoder history here is exactly one crash
/// away at all times: slicing past the end is fatal, and this input is hostile.
struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isDrained: Bool { offset == bytes.count }

    mutating func byte() -> UInt8? {
        guard offset < bytes.count else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func int32() -> Int32? {
        guard offset + 4 <= bytes.count else { return nil }
        var value: UInt32 = 0
        for i in (0..<4).reversed() { value = value << 8 | UInt32(bytes[offset + i]) }
        offset += 4
        return Int32(bitPattern: value)
    }

    mutating func float() -> Double? {
        guard offset + 4 <= bytes.count else { return nil }
        var bits: UInt32 = 0
        for i in (0..<4).reversed() { bits = bits << 8 | UInt32(bytes[offset + i]) }
        offset += 4
        return Double(Float(bitPattern: bits))
    }
}

extension [UInt8] {
    fileprivate mutating func appendInt32(_ value: Int32) {
        let bits = UInt32(bitPattern: value)
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8(truncatingIfNeeded: bits >> UInt32(shift)))
        }
    }

    fileprivate mutating func appendFloat(_ value: Double) {
        let bits = Float(value).bitPattern
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8(truncatingIfNeeded: bits >> UInt32(shift)))
        }
    }
}
