import Foundation

/// **Your own tracks**, as a versioned envelope — the same shape as
/// `HiscoreBook`, and stored the same way (JSON in Application Support, via a
/// dumb shim in SkidKit).
///
/// Replaces the single "My track" slot. The ordering is the book's, so the
/// picker has a stable list rather than whatever a dictionary hands back.
public struct TrackLibraryBook: Equatable, Sendable, Codable {
    public static let currentVersion = 1

    public var version = TrackLibraryBook.currentVersion
    public var tracks: [Entry] = []

    public init() {}

    /// One track in the library.
    ///
    /// **Identity is a UUID, never the name.** Two imported tracks will be
    /// called "Hairpin" sooner or later, and hiscores key on the track id — so a
    /// rename must not orphan them.
    ///
    /// The name and the dates live HERE, not in the share code: a code carries
    /// content only, so a signature attests to the road rather than to what one
    /// device happens to call it.
    public struct Entry: Equatable, Sendable, Codable, Identifiable {
        public var id: UUID
        public var name: String
        /// The share code — the content, and the source of truth for the track.
        public var code: String
        /// Who signed the code this entry was created from, if anyone, and
        /// whether it checked out **at that moment**.
        ///
        /// Cached rather than re-derived: the picker would otherwise verify on
        /// every render, which is the mistake the compile-per-frame slot made.
        public var authorKey: [UInt8]?
        public var signatureIsValid: Bool
        /// Made here. For an imported track this is when it arrived, since the
        /// author's own clock isn't something this device can know.
        public var createdAt: Date
        /// When it arrived from elsewhere; nil for one built here.
        public var importedAt: Date?
        /// Last edited here.
        public var updatedAt: Date

        public init(
            id: UUID, name: String, code: String, authorKey: [UInt8]? = nil,
            signatureIsValid: Bool = false, createdAt: Date, importedAt: Date? = nil,
            updatedAt: Date
        ) {
            self.id = id
            self.name = name
            self.code = code
            self.authorKey = authorKey
            self.signatureIsValid = signatureIsValid
            self.createdAt = createdAt
            self.importedAt = importedAt
            self.updatedAt = updatedAt
        }

        /// The id a compiled `Track` races under, so hiscores keep working
        /// unchanged — they key on a string, and built-ins keep their slugs.
        public var trackID: String { id.uuidString }

        /// Whether this entry came from somewhere else.
        public var isImported: Bool { importedAt != nil }
    }

    /// Newest activity first — what a picker shows.
    public var byRecency: [Entry] {
        tracks.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func entry(id: UUID) -> Entry? {
        tracks.first { $0.id == id }
    }

    /// Add a track, or replace one with the same id.
    public mutating func put(_ entry: Entry) {
        if let index = tracks.firstIndex(where: { $0.id == entry.id }) {
            tracks[index] = entry
        } else {
            tracks.append(entry)
        }
    }

    public mutating func remove(id: UUID) {
        tracks.removeAll { $0.id == id }
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// nil on garbage or a future version this build doesn't understand — the
    /// caller starts fresh rather than crashing on data it cannot read.
    public static func decode(_ data: Data) -> TrackLibraryBook? {
        guard let book = try? JSONDecoder().decode(TrackLibraryBook.self, from: data),
            book.version <= currentVersion
        else { return nil }
        return book
    }
}

extension TrackLibraryBook {
    /// **Fold the old single slot into the library**, once.
    ///
    /// Pure so the risky part of the move is testable: the caller reads the old
    /// UserDefaults string and supplies the clock. Idempotent by construction —
    /// a book that already has tracks is left alone, so a second run cannot
    /// duplicate the entry.
    public static func migrating(
        legacyCode: String?, into book: TrackLibraryBook, id: UUID, now: Date,
        name: String
    ) -> TrackLibraryBook {
        guard book.tracks.isEmpty, let legacyCode, !legacyCode.isEmpty else { return book }
        var migrated = book
        migrated.put(
            Entry(
                id: id, name: name, code: legacyCode,
                createdAt: now, updatedAt: now))
        return migrated
    }
}
