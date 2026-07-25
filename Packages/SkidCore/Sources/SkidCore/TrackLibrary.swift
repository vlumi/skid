import Foundation

/// The built-in tracks, as **share codes** — the exact strings the editor's Copy
/// button produces.
///
/// This replaces the old bundled-JSON `TrackDesign` library and its separate
/// compiler. A built-in is now just a track someone built in the editor and
/// pasted here, compiled by the same `PieceCompiler` as a player's own design.
/// One code path, one geometry model, and a built-in can be opened in the editor
/// and tweaked like anything else.
///
/// Codes are canonical and byte-stable, so they're safe to hold in source.
public enum TrackLibrary {
    /// A built-in: a display name and the code it compiles from.
    public struct Builtin: Sendable {
        public var id: String
        public var name: String
        public var code: String
    }

    public static let builtins: [Builtin] = [
        Builtin(id: "small", name: "Small track", code: "AQcBCh8MDAwJAAAKDBoCAwAIAwMFA0gCWAA"),
        Builtin(id: "oval", name: "Big oval", code: "AdcBCB8NDQEBDQ0BAgUAAQIEBgMFBLAGGAA"),
        Builtin(id: "eight", name: "Eight", code: "ARMBDR8LAAsLHQEeDAwADAECBAADBgkDBQNIAtAB"),
    ]

    /// Every built-in, compiled once. A code that doesn't compile is a broken
    /// build, not a runtime condition to limp through — the same stance the old
    /// bundled-design library took.
    public static let all: [Track] = builtins.map { builtin in
        do {
            return try PieceCompiler.compile(TrackCode.decode(builtin.code), id: builtin.id)
        } catch {
            fatalError("built-in track '\(builtin.id)' failed to compile: \(error)")
        }
    }

    /// Lookup by stable id; unknown ids fall back to the first track.
    public static func track(id: String) -> Track {
        all.first { $0.id == id } ?? all[0]
    }

    /// The display name for a track id.
    public static func displayName(id: String) -> String {
        builtins.first { $0.id == id }?.name ?? id
    }

    /// The layout behind a built-in — what "edit a copy of this track" needs.
    public static func layout(id: String) -> TrackLayout? {
        guard let builtin = builtins.first(where: { $0.id == id }) else { return nil }
        return try? TrackCode.decode(builtin.code)
    }

    /// A simple flat ring, for tests and demos that just need a track.
    public static func testRing() -> Track { track(id: "small") }
}
