import Foundation

/// The share code: a `TrackLayout` ↔ a short `base64url` string, carried at
/// `skid.misaki.fi/t/<code>`. Layout is `version · CRC-8 · TLV sections`
/// (design doc §Encoding). Canonical bytes — one encoding per track — so a
/// code is a stable identity, and typos fail cleanly via the CRC.
public enum TrackCode {
    public enum DecodeError: Error, Equatable {
        case notBase64
        case truncated
        case badVersion(Int)
        case badCRC
        case missingSection
        case duplicateSection
        case tooLarge
        /// Origin position wasn't a whole-unit integer (u16 range).
        case badOrigin
        /// The fitters section was malformed: not a whole number of 8-byte
        /// entries, or a radius index the catalog doesn't have.
        case badFitter
        /// The decals section wasn't a whole number of 2-byte entries.
        case badDecal
    }

    public static let version = 1

    // Hard caps — decode parses UNTRUSTED input from a URL, so every count is
    // bounded before anything is allocated or trusted.
    /// Longest share code accepted (chars) — a generous ceiling over the
    /// worst-case design budget, so a giant string is rejected up front.
    public static let maxCodeLength = 512
    /// Max pieces (also the layout cap); max gates per the design.
    /// Cap on **encoded** ids — the decode-work bound for hostile input.
    public static let maxPieces = 64
    /// Cap on **expanded** primitives — the track-length bound.
    ///
    /// Under 128 on purpose: a seam index addresses a primitive, and a varint's
    /// first byte carries 7 bits. For scale, real tracks are 15–21 primitives, and
    /// 127 short straights end to end is 15,240 units against a canvas perimeter of
    /// 5,866 — about 2.6 laps of the outer edge.
    public static let maxLength = 127
    public static let maxGates = 16

    private enum Tag: UInt8 {
        case pieces = 1
        case gates = 2
        case origin = 3
        case theme = 4
        /// The layout's baseline height, in HALF levels (the lattice step), as
        /// a signed byte. Omitted when the track starts on the ground, so every
        /// ground-level code keeps its exact bytes.
        case baseHeight = 5
        /// Solved fitter shapes, 8 bytes each: piece index, radius index and
        /// side, then the angle and the middle length as 24-bit fixed point.
        /// Omitted entirely when a track has no fitters, so codes for ordinary
        /// tracks are byte-identical to before this existed.
        case fitters = 6
        /// Decals on laid pieces, 2 bytes each: piece index, then the decal's
        /// raw value. Sparse and omitted entirely when a track has no decals, so
        /// codes for undecorated tracks stay byte-identical.
        case decals = 7
    }

    // MARK: - Encode

    public static func encode(_ layout: TrackLayout) -> String {
        // One track, one code: a closed ring is rotated to its canonical
        // starting piece first, so the same track built from different starting
        // points does not produce different codes. An open chain is untouched.
        let layout = layout.normalized()
        var body: [UInt8] = []
        // Packed into compounds at the byte boundary only — the layout itself is
        // always primitives (see `PiecePacking`).
        appendSection(
            &body, .pieces,
            encodeVarintIDs(
                PiecePacking.pack(
                    layout.pieces.indices.map { (layout.pieces[$0], layout.pitch(at: $0)) })))
        appendSection(&body, .gates, layout.gateSeams.map { UInt8(truncatingIfNeeded: $0) })
        appendSection(&body, .origin, encodeOrigin(layout.origin))
        if layout.theme != .normal {
            appendSection(&body, .theme, [UInt8(layout.theme.rawValue)])
        }
        if !layout.fitters.isEmpty {
            appendSection(&body, .fitters, encodeFitters(layout.fitters))
        }
        if !layout.decals.isEmpty {
            appendSection(&body, .decals, encodeDecals(layout.decals, count: layout.pieces.count))
        }
        if layout.originHeight != 0 {
            let halves = Int((layout.originHeight / (Track.levelHeight / 2)).rounded())
            appendSection(&body, .baseHeight, [UInt8(bitPattern: Int8(halves))])
        }

        var blob: [UInt8] = [UInt8(version), crc8(body)]
        blob.append(contentsOf: body)
        return base64urlEncode(blob)
    }

    // MARK: - Decode

    /// Decode a share code. Treats the input as **hostile**: the string
    /// length is capped before decoding, every TLV length is bounds-checked,
    /// sections may not repeat, and the piece/gate counts are capped — so a crafted URL can only ever produce a bounded,
    /// well-formed `TrackLayout` or a thrown error, never a crash or a
    /// runaway allocation. (Whether that layout is *saveable* is a separate
    /// question for the validator / compiler.)
    public static func decode(_ code: String) throws -> TrackLayout {
        guard code.count <= maxCodeLength else { throw DecodeError.tooLarge }
        guard let blob = base64urlDecode(code) else { throw DecodeError.notBase64 }
        guard blob.count >= 2 else { throw DecodeError.truncated }
        guard Int(blob[0]) == version else { throw DecodeError.badVersion(Int(blob[0])) }
        let body = Array(blob[2...])
        guard crc8(body) == blob[1] else { throw DecodeError.badCRC }

        let sections = try parseSections(body)

        guard let piecesPayload = sections[.pieces],
            let gatesPayload = sections[.gates],
            let originPayload = sections[.origin]
        else { throw DecodeError.missingSection }

        // Two DISTINCT caps, and conflating them is a real hazard. `maxPieces`
        // bounds the ENCODED ids — how much decode work a hostile code may demand.
        // `maxLength` bounds the TRACK after expansion, and it's the one that must
        // hold, since a seam index addresses a primitive. Checking only the encoded
        // count would let 64 compounds expand to 256 primitives unnoticed, which is
        // why the expansion is bounded as it proceeds rather than measured after.
        let encoded = try decodeVarintIDs(piecesPayload)
        guard encoded.count <= maxPieces else { throw DecodeError.tooLarge }
        guard let resolved = PiecePacking.unpack(encoded, limit: maxLength) else {
            throw DecodeError.tooLarge
        }
        let pieces = resolved.map(\.id)
        let pitches = resolved.map(\.pitch)
        let gates = gatesPayload.map { Int($0) }
        guard gates.count <= maxGates else { throw DecodeError.tooLarge }
        let origin = try decodeOrigin(originPayload)
        let themeByte = sections[.theme].flatMap { $0.first }
        let theme = themeByte.flatMap { TrackLayout.Theme(rawValue: Int($0)) } ?? .normal
        let baseHalves = sections[.baseHeight].flatMap { $0.first }.map {
            Int(Int8(bitPattern: $0))
        }
        let originHeight = Double(baseHalves ?? 0) * (Track.levelHeight / 2)
        let fitters =
            try sections[.fitters].map {
                try decodeFitters($0, pieceCount: pieces.count)
            } ?? [:]
        let decals =
            try sections[.decals].map {
                try decodeDecals($0, count: pieces.count)
            } ?? [:]
        // Hostile input: a baseline outside the world's storeys is refused here,
        // before anything walks or allocates.
        guard Track.withinLevels(originHeight) else { throw DecodeError.tooLarge }

        return TrackLayout(
            pieces: pieces, pitches: pitches, origin: origin, originHeight: originHeight,
            gateSeams: gates, theme: theme, fitters: fitters, decals: decals)
    }

    /// Parse the TLV body into known sections, bounds-checking every step.
    /// Unknown tags are skipped by length (forward compatibility); a repeated
    /// known tag, an overrunning length, or trailing bytes are all rejected —
    /// canonical, so one blob has one meaning.
    private static func parseSections(_ body: [UInt8]) throws -> [Tag: [UInt8]] {
        var sections: [Tag: [UInt8]] = [:]
        var i = 0
        while i < body.count {
            guard i + 2 <= body.count else { throw DecodeError.truncated }
            let tagByte = body[i]
            let len = Int(body[i + 1])
            let start = i + 2
            guard start + len <= body.count else { throw DecodeError.truncated }
            if let tag = Tag(rawValue: tagByte) {
                guard sections[tag] == nil else { throw DecodeError.duplicateSection }
                sections[tag] = Array(body[start..<start + len])
            }
            i = start + len
        }
        // Every advance is bounded by the guard above, so this cannot overrun.
        // An assertion, not a thrown error: tripping it means the loop changed,
        // not that the input was bad.
        assert(i == body.count)
        return sections
    }

    // MARK: - Sections

    private static func appendSection(_ body: inout [UInt8], _ tag: Tag, _ payload: [UInt8]) {
        body.append(tag.rawValue)
        body.append(UInt8(truncatingIfNeeded: payload.count))
        body.append(contentsOf: payload)
    }

    /// Piece ids as varints: 0…127 one byte; ≥128 a two-byte big-endian value
    /// with the high bit of the first byte set (15-bit, ~32k ids).
    /// Fitters as 8 bytes each, sorted by index so the encoding is canonical:
    /// index, then radius-and-side packed into one byte, then the angle and the
    /// middle length as 24-bit big-endian fixed point.
    ///
    /// The quantization is NOT applied here — a solved fitter is already snapped
    /// to this grid (see `Fitter.quantized`), so encoding is lossless and the
    /// shape a decoder walks is exactly the shape the author's device walked.
    private static func encodeFitters(_ fitters: [Int: Fitter]) -> [UInt8] {
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
    private static func encodeDecals(_ decals: [Int: Decal], count: Int) -> [UInt8] {
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
    private static func decodeDecals(_ bytes: [UInt8], count: Int) throws -> [Int: Decal] {
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

    private static func decodeFitters(
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

    private static func bytes24(_ value: Int) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ]
    }

    private static func value24(_ slice: ArraySlice<UInt8>) -> Int {
        slice.reduce(0) { ($0 << 8) | Int($1) }
    }

    private static func encodeVarintIDs(_ ids: [PieceID]) -> [UInt8] {
        var out: [UInt8] = []
        for id in ids {
            if id < 128 {
                out.append(UInt8(id))
            } else {
                out.append(UInt8(0x80 | (id >> 8)))
                out.append(UInt8(id & 0xFF))
            }
        }
        return out
    }

    private static func decodeVarintIDs(_ bytes: [UInt8]) throws -> [PieceID] {
        var out: [PieceID] = []
        var i = 0
        while i < bytes.count {
            let b0 = bytes[i]
            if b0 & 0x80 == 0 {
                out.append(Int(b0))
                i += 1
            } else {
                guard i + 1 < bytes.count else { throw DecodeError.truncated }
                out.append((Int(b0 & 0x7F) << 8) | Int(bytes[i + 1]))
                i += 2
            }
        }
        return out
    }

    /// Origin: x:u16 · y:u16 (whole canvas units) · heading:u8. The origin
    /// sits on a coarse snap grid, so its position is integer-valued.
    private static func encodeOrigin(_ pose: PiecePose) -> [UInt8] {
        let x = wholeUnits(pose.position.x)
        let y = wholeUnits(pose.position.y)
        return [
            UInt8(x >> 8), UInt8(x & 0xFF),
            UInt8(y >> 8), UInt8(y & 0xFF),
            UInt8(pose.heading.step),
        ]
    }

    private static func decodeOrigin(_ bytes: [UInt8]) throws -> PiecePose {
        guard bytes.count >= 5 else { throw DecodeError.truncated }
        let x = Int(bytes[0]) << 8 | Int(bytes[1])
        let y = Int(bytes[2]) << 8 | Int(bytes[3])
        return PiecePose(
            position: CoordPoint(x, y), heading: Heading(Int(bytes[4])))
    }

    /// A `Coord` that is a whole integer (b == 0) as a non-negative u16, else
    /// throws — the origin must be grid-aligned to encode.
    private static func wholeUnits(_ c: Coord) -> Int {
        // value = a/2 when b == 0; the origin snap grid keeps `a` even and ≥ 0.
        max(0, min(0xFFFF, c.a / 2))
    }

    // MARK: - CRC-8 (poly 0x07, init 0x00)

    static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 {
                crc = (crc & 0x80) != 0 ? (crc << 1) ^ 0x07 : (crc << 1)
            }
        }
        return crc
    }

    // MARK: - base64url (no padding)

    private static func base64urlEncode(_ bytes: [UInt8]) -> String {
        let b64 = Data(bytes).base64EncodedString()
        return b64.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64urlDecode(_ s: String) -> [UInt8]? {
        var b64 = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return [UInt8](data)
    }
}
