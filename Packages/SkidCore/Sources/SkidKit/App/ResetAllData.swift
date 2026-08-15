import Foundation
import SkidCore

/// **Wipe everything this app has ever stored.**
///
/// A development tool: the tracks, the records and the dials all persist, and while the
/// game is being built they regularly need to go back to nothing — a stale record set on
/// a road that has since moved, a library full of test tracks, a car tuned three sessions
/// ago that quietly records nothing.
///
/// The whole point is that it is *complete*, so it is written as one place that knows
/// every store rather than a button that remembers most of them:
///
/// - **The JSON files** in Application Support: tracks, profiles, hiscores.
/// - **Every `UserDefaults` key under `skid.`** — the tuning dials, the d-pad shape, the
///   editor's hotbar, the debug overlay, and the legacy custom-track slot. Swept by
///   PREFIX rather than by a list of names, because a list is a thing to forget to update:
///   a dial added next month is wiped by this without anybody remembering to come back.
///
/// It does not reset the in-memory game — the caller does that, since only it knows what
/// is on screen.
enum ResetAllData {
    /// Every `UserDefaults` key this app owns starts with this.
    static let keyPrefix = "skid."

    /// The Application Support directory the files live in.
    static func directory() -> URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Skid", isDirectory: true)
    }

    /// Delete the stored files and every `skid.` default.
    ///
    /// `defaults` is injectable so tests can prove the sweep without emptying the
    /// developer's own dials — the standard store is process-wide.
    static func wipe(
        defaults: UserDefaults = .standard,
        directory: URL = ResetAllData.directory()
    ) {
        let manager = FileManager.default
        for file in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? [] {
            guard file.hasSuffix(".json") else { continue }
            try? manager.removeItem(at: directory.appendingPathComponent(file))
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
