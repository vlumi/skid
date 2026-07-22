import Foundation

/// One track design on disk: a versioned envelope (like `HiscoreBook`) so
/// the format can evolve without eating old files — tolerant decode returns
/// nil on garbage or a future version this build doesn't understand.
public struct TrackDesignFile: Equatable, Sendable, Codable {
    public static let currentVersion = 1

    public var version = TrackDesignFile.currentVersion
    public var design: TrackDesign

    public init(design: TrackDesign) {
        self.design = design
    }

    /// Canonical bytes: sorted keys + pretty printing so re-encoding an
    /// unchanged design is byte-identical — track files diff cleanly in
    /// git and hand-edit drift is detectable.
    public func encoded() throws -> Data {
        try Self.canonicalEncoder.encode(self)
    }

    /// nil on garbage or a future version.
    public static func decode(_ data: Data) -> TrackDesignFile? {
        guard let file = try? JSONDecoder().decode(TrackDesignFile.self, from: data),
            file.version <= currentVersion
        else { return nil }
        return file
    }

    static var canonicalEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }
}

/// The bundled-track roster: which designs ship, in picker order. A
/// separate manifest (not an order field per file) so inserting a track
/// never renumbers the others.
public struct TrackManifest: Equatable, Sendable, Codable {
    public static let currentVersion = 1

    public var version = TrackManifest.currentVersion
    /// Track ids, in picker order.
    public var tracks: [String]

    public init(tracks: [String]) {
        self.tracks = tracks
    }

    public func encoded() throws -> Data {
        try TrackDesignFile.canonicalEncoder.encode(self)
    }

    public static func decode(_ data: Data) -> TrackManifest? {
        guard let manifest = try? JSONDecoder().decode(TrackManifest.self, from: data),
            manifest.version <= currentVersion
        else { return nil }
        return manifest
    }
}
