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
    /// Longest payload a TLV section can carry: the length is one byte.
    ///
    /// Not slack — decals are 2 bytes each and `maxLength` caps a layout at 127
    /// primitives, so a fully decorated track sits at 254, one byte under.
    public static let maxSectionPayload = 255

    /// Bytes a section of `n` decals would occupy, for the tests that pin how
    /// close that is to the ceiling.
    static func sectionPayloadSize(decals count: Int) -> Int { count * 2 }

    /// The length `encode` would produce. Defined as the encode itself, so the
    /// two cannot drift; keep it off render paths, which already pay for one
    /// encode per edit through the undo snapshot.
    public static func encodedSize(_ layout: TrackLayout) -> Int {
        encode(layout).count
    }

    enum Tag: UInt8 {
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
        /// Which laid pieces carry guard railings, one byte per railed piece: the
        /// piece index. One bit of information per piece, so unlike decals there
        /// is no value byte to pair with it. Sparse and omitted entirely when a
        /// track has no railings at all.
        case railed = 8
        /// **How far each warp piece drops the road**, two bytes per warp: the piece
        /// index, then the drop in signed HALF-LEVELS (the same quantum `baseHeight`
        /// uses). Two bytes rather than a packed field because a warp is rare — a
        /// track has a handful at most — and a plain pair is far easier to read back
        /// than bit-fiddling for the sake of a byte nobody notices.
        ///
        /// A warp with no entry drops one level, so the common deck-to-ground jump
        /// costs nothing to encode.
        case warpDrops = 9
        /// What kind of road this is (`TrackLayout.RoadStyle`), one byte. Omitted for
        /// a circuit, so every existing code keeps its exact bytes.
        case roadStyle = 10
        /// A 32-byte raw Ed25519 public key — who signed this. High on purpose:
        /// tags cost the same wherever they sit, so the low contiguous range
        /// stays for CONTENT and the top holds the envelope.
        case pubkey = 254
        /// The signature, over everything before it. Must be the LAST record.
        case sig = 255

        /// Whether this section describes the ROAD, as opposed to who shared it
        /// or what they call it.
        ///
        /// The split is the tag range itself, not a list to keep in step: the
        /// low contiguous range is content, the top is envelope. A new envelope
        /// section is therefore excluded from a track's identity by default,
        /// which is the safe direction to fail.
        var isContent: Bool { rawValue < firstEnvelopeTag }
    }

    /// Where the envelope range starts. Content sections live below it.
    static let firstEnvelopeTag: UInt8 = 128

    // MARK: - Encode

    public static func encode(_ layout: TrackLayout) -> String {
        finish(encodedBody(layout))
    }

    /// The TLV records for a layout, without the version+CRC header — the part
    /// a signature covers. Shared with `encode(_:signedBy:)`, which appends its
    /// own sections before framing.
    static func encodedBody(_ layout: TrackLayout) -> [UInt8] {
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
        if layout.roadStyle != .circuit {
            appendSection(&body, .roadStyle, [UInt8(layout.roadStyle.rawValue)])
        }
        if !layout.fitters.isEmpty {
            appendSection(&body, .fitters, encodeFitters(layout.fitters))
        }
        if !layout.decals.isEmpty {
            appendSection(&body, .decals, encodeDecals(layout.decals, count: layout.pieces.count))
        }
        if !layout.railed.isEmpty {
            appendSection(&body, .railed, encodeRailed(layout.railed, count: layout.pieces.count))
        }
        let warps = encodeWarpDrops(layout.warpDrops, count: layout.pieces.count)
        if !warps.isEmpty {
            appendSection(&body, .warpDrops, warps)
        }
        if layout.originHeight != 0 {
            let halves = Int((layout.originHeight / (Track.levelHeight / 2)).rounded())
            appendSection(&body, .baseHeight, [UInt8(bitPattern: Int8(halves))])
        }
        return body
    }

    /// Version byte, CRC over the body, then the body. The CRC covers a
    /// signature section too — it is an integrity check over the final artifact,
    /// while the signature covers content, so they nest rather than overlap.
    static func finish(_ body: [UInt8]) -> String {
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
        // An unknown style decodes as a circuit rather than failing: a code from a later
        // build should still be raceable, just plainer.
        let styleByte = sections[.roadStyle].flatMap { $0.first }
        let roadStyle =
            styleByte.flatMap { TrackLayout.RoadStyle(rawValue: Int($0)) } ?? .circuit
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
        let railed = sections[.railed].map { decodeRailed($0, count: pieces.count) } ?? []
        let warpDrops =
            sections[.warpDrops].map { decodeWarpDrops($0, count: pieces.count) } ?? [:]
        // Hostile input: a baseline outside the world's storeys is refused here,
        // before anything walks or allocates.
        guard Track.withinLevels(originHeight) else { throw DecodeError.tooLarge }

        return TrackLayout(
            pieces: pieces, pitches: pitches, origin: origin, originHeight: originHeight,
            gateSeams: gates, theme: theme, roadStyle: roadStyle, fitters: fitters,
            decals: decals,
            railed: railed, warpDrops: warpDrops)
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

    static func appendSection(_ body: inout [UInt8], _ tag: Tag, _ payload: [UInt8]) {
        // A wrapped length desynchronizes the parser, so `encode` would emit a
        // code its own `decode` rejects — silently, since `encode` cannot throw.
        // Unreachable by construction today; this catches the encoder growing a
        // section past what a one-byte length can describe.
        precondition(
            payload.count <= maxSectionPayload,
            "section \(tag) payload \(payload.count) exceeds the one-byte length")
        body.append(tag.rawValue)
        body.append(UInt8(payload.count))
        body.append(contentsOf: payload)
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

    static func base64urlEncode(_ bytes: [UInt8]) -> String {
        let b64 = Data(bytes).base64EncodedString()
        return b64.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64urlDecode(_ s: String) -> [UInt8]? {
        var b64 = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return [UInt8](data)
    }
}
