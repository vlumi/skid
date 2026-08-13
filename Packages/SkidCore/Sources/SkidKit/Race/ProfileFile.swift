import Foundation
import SkidCore

/// Loads/saves the profile book as JSON in Application Support, beside the hiscores
/// and the track library. All the interesting logic — versioning, the cap, the recency
/// ordering — lives in `ProfileBook` in the core, where it is tested.
///
/// Deliberately a near-copy of `HiscoreFile`: same directory, same atomic write, same
/// "unreadable means empty" stance. A profile book that failed to parse must not stop
/// the app starting — a guest can always race, which is the whole point of guests.
@MainActor
public final class ProfileFile {
    private let url: URL

    /// `filename` is injectable for the same reason `TrackLibraryFile`'s is: a fixed
    /// path is process-wide state, and tests that shared one profile file would leak
    /// identities between methods.
    public init(filename: String = "profiles.json") {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Skid", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent(filename)
    }

    public func load() -> ProfileBook {
        guard let data = try? Data(contentsOf: url), let book = ProfileBook.decode(data) else {
            return ProfileBook()
        }
        return book
    }

    public func save(_ book: ProfileBook) {
        guard let data = try? book.encoded() else { return }
        try? data.write(to: url, options: .atomic)
    }
}
