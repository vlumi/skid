import Foundation
import SkidCore

/// Loads/saves the track library as JSON in Application Support, beside the
/// hiscores. Everything interesting — identity, versioning, migration — lives
/// in `TrackLibraryBook` in the core, where it is tested.
@MainActor
public final class TrackLibraryFile {
    private let url: URL

    public init(filename: String = "tracks.json") {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Skid", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent(filename)
    }

    /// An unreadable or absent file gives an empty library rather than an
    /// error: a player with no tracks yet is the normal first launch.
    public func load() -> TrackLibraryBook {
        guard let data = try? Data(contentsOf: url),
            let book = TrackLibraryBook.decode(data)
        else { return TrackLibraryBook() }
        return book
    }

    public func save(_ book: TrackLibraryBook) {
        guard let data = try? book.encoded() else { return }
        try? data.write(to: url, options: .atomic)
    }
}
