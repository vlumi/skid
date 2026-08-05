import Foundation

/// **The index-keyed sections** of a share code: fitters, railings, warp drops and
/// decals.
///
/// One shape, four times over — a piece index paired with (for all but railings) a
/// value — so they belong together, and together they are what every layout mutation
/// has to remap. Split out of `TrackCode.swift` on the file-length limit.
///
/// All four assume **hostile input**: an index past the pieces, a truncated pair or
/// a nonsense value is dropped rather than trusted, since a share code arrives from
/// a stranger.
extension TrackCode {
    /// Piece ids as varints: 0…127 one byte; ≥128 a two-byte big-endian value
    /// with the high bit of the first byte set (15-bit, ~32k ids).
    /// Fitters as 8 bytes each, sorted by index so the encoding is canonical:
    /// index, then radius-and-side packed into one byte, then the angle and the
    /// middle length as 24-bit big-endian fixed point.
    ///
    /// The quantization is NOT applied here — a solved fitter is already snapped
    /// to this grid (see `Fitter.quantized`), so encoding is lossless and the
    /// shape a decoder walks is exactly the shape the author's device walked.
    static func encodeFitters(_ fitters: [Int: Fitter]) -> [UInt8] {
        var out: [UInt8] = []
        for (index, fitter) in fitters.sorted(by: { $0.key < $1.key }) {
            out.append(UInt8(truncatingIfNeeded: index))
            let radius = fitter.radiusIndex ?? 0
            out.append(UInt8(radius) | (fitter.stepsLeft ? 0x80 : 0))
            out.append(contentsOf: bytes24(Fitter.quantizedAngle(fitter.angle)))
            out.append(contentsOf: bytes24(Fitter.quantizedLength(fitter.length)))
        }
        return out
    }

    /// Two bytes per decal: piece index, then the decal's raw value. Sorted by
    /// index so the bytes are canonical, and entries outside the piece list are
    /// dropped rather than encoded — a decal on a piece that isn't there is not a
    /// track feature, it's a stale key.
    /// Railed piece indices, ascending so one layout has one spelling.
    static func encodeRailed(_ railed: Set<Int>, count: Int) -> [UInt8] {
        railed.sorted().filter { (0..<count).contains($0) }
            .map { UInt8(truncatingIfNeeded: $0) }
    }

    /// Railings from their section, hostile input assumed: an index past the
    /// pieces is dropped rather than trusted. Duplicates collapse — it is a set.
    static func decodeRailed(_ bytes: [UInt8], count: Int) -> Set<Int> {
        Set(bytes.map(Int.init).filter { (0..<count).contains($0) })
    }

    /// Warp drops as (index, half-levels) pairs, ascending so one layout has one
    /// spelling. A drop of exactly one level is the DEFAULT, so it is omitted —
    /// which keeps the ordinary jump free and the section absent on most tracks.
    static func encodeWarpDrops(_ drops: [Int: Double], count: Int) -> [UInt8] {
        var out: [UInt8] = []
        for (index, drop) in drops.sorted(by: { $0.key < $1.key })
        where (0..<count).contains(index) {
            let halves = Int((drop / (Track.levelHeight / 2)).rounded())
            guard halves != -2, halves >= -127, halves <= 0 else { continue }
            out.append(UInt8(truncatingIfNeeded: index))
            out.append(UInt8(bitPattern: Int8(halves)))
        }
        return out
    }

    /// Warp drops from their section, hostile input assumed: a trailing odd byte, an
    /// index past the pieces, or an upward "drop" is dropped rather than trusted.
    static func decodeWarpDrops(_ bytes: [UInt8], count: Int) -> [Int: Double] {
        var out: [Int: Double] = [:]
        for pair in stride(from: 0, to: bytes.count - 1, by: 2) {
            let index = Int(bytes[pair])
            guard (0..<count).contains(index) else { continue }
            let halves = Int(Int8(bitPattern: bytes[pair + 1]))
            guard halves <= 0 else { continue }
            out[index] = Double(halves) * Track.levelHeight / 2
        }
        return out
    }

    static func encodeDecals(_ decals: [Int: Decal], count: Int) -> [UInt8] {
        var out: [UInt8] = []
        for (index, decal) in decals.sorted(by: { $0.key < $1.key })
        where (0..<count).contains(index) {
            out.append(UInt8(truncatingIfNeeded: index))
            out.append(UInt8(truncatingIfNeeded: decal.rawValue))
        }
        return out
    }

    /// Decals from their section, hostile input assumed: a wrong length, an index
    /// past the pieces, or an unknown decal id is dropped rather than trusted.
    static func decodeDecals(_ bytes: [UInt8], count: Int) throws -> [Int: Decal] {
        guard bytes.count % 2 == 0 else { throw DecodeError.badDecal }
        var out: [Int: Decal] = [:]
        for pair in stride(from: 0, to: bytes.count, by: 2) {
            let index = Int(bytes[pair])
            guard (0..<count).contains(index), let decal = Decal(rawValue: Int(bytes[pair + 1]))
            else { continue }
            out[index] = decal
        }
        return out
    }

    static func decodeFitters(
        _ payload: [UInt8], pieceCount: Int
    ) throws -> [Int: Fitter] {
        guard payload.count % 8 == 0 else { throw DecodeError.badFitter }
        var out: [Int: Fitter] = [:]
        for start in stride(from: 0, to: payload.count, by: 8) {
            let index = Int(payload[start])
            // The index must address a real piece: a shape with nothing to attach
            // to is malformed, not merely unused.
            guard index < pieceCount else { throw DecodeError.badFitter }
            let radiusByte = payload[start + 1]
            let radiusIndex = Int(radiusByte & 0x7F)
            guard Fitter.radii.indices.contains(radiusIndex) else {
                throw DecodeError.badFitter
            }
            let angle = Fitter.dequantizedAngle(
                value24(payload[(start + 2)..<(start + 5)]))
            let length = Fitter.dequantizedLength(
                value24(payload[(start + 5)..<(start + 8)]))
            out[index] = Fitter(
                radius: Fitter.radii[radiusIndex], angle: angle, length: length,
                stepsLeft: radiusByte & 0x80 != 0)
        }
        return out
    }

    static func bytes24(_ value: Int) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ]
    }

    static func value24(_ slice: ArraySlice<UInt8>) -> Int {
        slice.reduce(0) { ($0 << 8) | Int($1) }
    }
}
