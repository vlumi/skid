import Foundation
import SkidCore

/// Loads/saves the hiscore book as JSON in Application Support. All the
/// interesting logic (versioning, improve-only records) lives in
/// `HiscoreBook` in the core, where it's tested.
@MainActor
public final class HiscoreFile {
    private let url: URL

    /// `filename` is injectable for the same reason the library's and the profiles' are:
    /// a fixed path is process-wide state, so tests would read and overwrite the real
    /// hiscore book — the developer's own records — and leak between methods.
    public init(filename: String = "hiscores.json") {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Skid", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent(filename)
    }

    public func load() -> HiscoreBook {
        guard let data = try? Data(contentsOf: url), let book = HiscoreBook.decode(data) else {
            return HiscoreBook()
        }
        return book
    }

    public func save(_ book: HiscoreBook) {
        guard let data = try? book.encoded() else { return }
        try? data.write(to: url, options: .atomic)
    }
}
