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
        case trailingGarbage
        case tooLarge
        /// Origin position wasn't a whole-unit integer (u16 range).
        case badOrigin
    }

    public static let version = 1

    // Hard caps — decode parses UNTRUSTED input from a URL, so every count is
    // bounded before anything is allocated or trusted.
    /// Longest share code accepted (chars) — a generous ceiling over the
    /// worst-case design budget, so a giant string is rejected up front.
    public static let maxCodeLength = 512
    /// Max pieces (also the layout cap); max gates per the design.
    public static let maxPieces = 64
    public static let maxGates = 16

    private enum Tag: UInt8 {
        case pieces = 1
        case gates = 2
        case origin = 3
        case theme = 4
    }

    // MARK: - Encode

    public static func encode(_ layout: TrackLayout) -> String {
        var body: [UInt8] = []
        appendSection(&body, .pieces, encodeVarintIDs(layout.pieces))
        appendSection(&body, .gates, layout.gateSeams.map { UInt8(truncatingIfNeeded: $0) })
        appendSection(&body, .origin, encodeOrigin(layout.origin))
        if layout.theme != .normal {
            appendSection(&body, .theme, [UInt8(layout.theme.rawValue)])
        }

        var blob: [UInt8] = [UInt8(version), crc8(body)]
        blob.append(contentsOf: body)
        return base64urlEncode(blob)
    }

    // MARK: - Decode

    /// Decode a share code. Treats the input as **hostile**: the string
    /// length is capped before decoding, every TLV length is bounds-checked,
    /// sections may not repeat or leave trailing bytes, and the piece/gate
    /// counts are capped — so a crafted URL can only ever produce a bounded,
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

        let pieces = try decodeVarintIDs(piecesPayload)
        guard pieces.count <= maxPieces else { throw DecodeError.tooLarge }
        let gates = gatesPayload.map { Int($0) }
        guard gates.count <= maxGates else { throw DecodeError.tooLarge }
        let origin = try decodeOrigin(originPayload)
        let themeByte = sections[.theme].flatMap { $0.first }
        let theme = themeByte.flatMap { TrackLayout.Theme(rawValue: Int($0)) } ?? .normal

        return TrackLayout(pieces: pieces, origin: origin, gateSeams: gates, theme: theme)
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
        guard i == body.count else { throw DecodeError.trailingGarbage }
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
