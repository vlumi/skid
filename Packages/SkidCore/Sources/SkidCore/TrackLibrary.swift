import Foundation

/// The built-in tracks, as **share codes** — the exact strings the editor's Copy
/// button produces.
///
/// A built-in is just a track someone built in the editor and pasted here,
/// compiled by the same `PieceCompiler` as a player's own design.
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

    /// Codes are under the **primitive layout** (seam N = primitive N's exit).
    ///
    /// Re-encoded when the layout became primitives: the pieces section still packs
    /// into compounds, but a decoded layout is primitives, so seam indices address
    /// primitives. An older code decodes to the wrong shape — its compound ids
    /// expand while its seams stay put — so codes from before this change must be
    /// re-copied out of the editor.
    public static let builtins: [Builtin] = [
        Builtin(id: "small", name: "Small track", code: "AUwBCB8SDAkBCgwaAgMABAwDBQNIAlgA"),
        Builtin(id: "oval", name: "Big oval", code: "Af8BBx8NDQINDQECBAACBgoDBQSwBhgA"),
        Builtin(
            id: "eight", name: "Eight", code: "AYUBCx8ReQUFAnoGBhIBAgMABAwDBQJYA8AHCAgFBgcICQoLDA"),
        // Built in the editor with the pitch tools, and the first built-in to
        // START off the ground: its baseline is the deck, so the lap dips to
        // ground level and climbs back. Exercises raised baselines, half-level
        // climbs and self-crossing at two heights all at once.
        Builtin(
            id: "clover", name: "Clover",
            code: "AQwBGR8eAQ95AwMBHgEPAwMBHgEPAwMBHgEPAwMCAwAXIwMFBLAFoAAIFwABAgkKCwwNDhUW"
                + "FxgZGiEiIyQlJi0uBQEC"),
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
        builtin(id: id) ?? all[0]
    }

    /// The built-in with this id, or nil. The fallback in `track(id:)` is a
    /// safety net for a picker aimed at a deleted track — it must not double as
    /// a licence to ship a dangling id, so anything that should resolve is
    /// asserted against this instead.
    public static func builtin(id: String) -> Track? {
        all.first { $0.id == id }
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
