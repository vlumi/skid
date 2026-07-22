import Foundation

/// Built-in tracks: `TrackDesign` JSON bundled under Resources/Tracks/
/// (the source of truth — `skid-tracks export` re-encodes it, the future
/// editor writes it), decoded and compiled once at first use. Every track:
/// closed asphalt ribbon in grass, directional corridor gates
/// (start/finish last), 4 grid slots, hazards as design.
public enum TrackLibrary {
    /// Every bundled design, in manifest order.
    public static let designs: [TrackDesign] = loadBundledDesigns()

    /// Every built-in track, compiled once — the bundled designs are
    /// build artifacts, so a failure here is a broken build, not a
    /// runtime condition to limp through.
    public static let all: [Track] = designs.map { design in
        do {
            return try design.compile()
        } catch {
            fatalError("bundled design '\(design.id)' failed to compile: \(error)")
        }
    }

    /// Lookup by stable id; unknown ids fall back to the first track.
    public static func track(id: String) -> Track {
        all.first { $0.id == id } ?? all[0]
    }

    /// The authored display name for a track id.
    public static func displayName(id: String) -> String {
        designs.first { $0.id == id }?.name ?? id
    }

    // Named accessors for the built-ins (tests and demos use these).
    public static func practiceLoop() -> Track { track(id: "practice-loop") }
    public static func gauntlet() -> Track { track(id: "gauntlet") }
    public static func hairpin() -> Track { track(id: "hairpin") }
    public static func overpass() -> Track { track(id: "overpass") }

    /// Raw bytes of a bundled file (tests verify canonical encoding).
    static func bundledData(resource: String) -> Data? {
        guard
            let url = Bundle.module.url(
                forResource: resource, withExtension: "json", subdirectory: "Tracks")
        else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func loadBundledDesigns() -> [TrackDesign] {
        guard
            let manifestData = bundledData(resource: "manifest"),
            let manifest = TrackManifest.decode(manifestData)
        else { fatalError("bundled track manifest is missing or unreadable") }
        return manifest.tracks.map { id in
            guard
                let data = bundledData(resource: id),
                let file = TrackDesignFile.decode(data)
            else { fatalError("bundled track design '\(id)' is missing or unreadable") }
            return file.design
        }
    }
}
