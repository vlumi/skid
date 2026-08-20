import Foundation
import SkidCore

/// **The setup survives quitting.** Who is racing, on which track, in which
/// mode — reported as "would be nice if they stayed the same when I restart
/// the app". One JSON file beside the profiles and hiscores, written whenever
/// any of it changes and read back on launch; launch arguments still override
/// it, since they are applied after the restore. A FILE, not `UserDefaults`:
/// the first cut used a defaults key, and because defaults are process-wide,
/// every test that touched an entrant leaked its setup into the next suite —
/// the same trap the tuning dials already document.
struct SetupMemory: Codable {
    var mode: CouchGame.Mode
    var trackID: String
    var entrants: [RaceEntrant]
    var schemes: [ControlScheme]
    var fillWithAI: Bool
    var aiDifficulty: AIDriver.Difficulty
    /// Per-slot palette picks. Optional so a file written before colors were
    /// remembered still restores everything else.
    var colorIndices: [Int]?
}

/// Loads/saves the setup memory as JSON in Application Support, beside the
/// profiles — a near-copy of `ProfileFile`, filename injectable for the same
/// reason: a fixed path is process-wide state.
@MainActor
public final class SetupFile {
    private let url: URL

    public init(filename: String = "setup.json") {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Skid", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent(filename)
    }

    func load() -> SetupMemory? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SetupMemory.self, from: data)
    }

    func save(_ memory: SetupMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension CouchGame {
    func saveSetupMemory() {
        setupFile.save(
            SetupMemory(
                mode: mode, trackID: trackID, entrants: entrants, schemes: schemes,
                fillWithAI: fillWithAI, aiDifficulty: aiDifficulty,
                colorIndices: colorIndices))
    }

    /// Restore what was saved, dropping anything that no longer exists: a
    /// track that was deleted falls back to the default pick, and an entrant
    /// whose profile is gone races as a guest rather than as a dangling id.
    func restoreSetupMemory() {
        guard let memory = setupFile.load() else { return }
        mode = memory.mode
        if TrackLibrary.builtin(id: memory.trackID) != nil
            || library.entry(id: memory.trackID) != nil
        {
            trackID = memory.trackID
        }
        let known = memory.entrants.map { entrant -> RaceEntrant in
            guard let id = entrant.profileID else { return entrant }
            return profiles.profile(id: id) != nil ? entrant : .guest
        }
        entrants = RaceField.nonEmpty(RaceField.capped(known, to: Self.maxCars))
        if memory.schemes.count == schemes.count {
            schemes = memory.schemes
        }
        fillWithAI = memory.fillWithAI
        aiDifficulty = memory.aiDifficulty
        // Colors restore only as the permutation the pickers maintain — a file
        // with duplicates or stray indices (hand-edited, or from a future
        // palette) would break the "no two seats alike" invariant every picker
        // assumes, so it is ignored rather than half-applied.
        if let colors = memory.colorIndices, colors.count == colorIndices.count,
            Set(colors) == Set(0..<Self.palette.count)
        {
            colorIndices = colors
        }
        syncSeatIdentities()
    }
}
