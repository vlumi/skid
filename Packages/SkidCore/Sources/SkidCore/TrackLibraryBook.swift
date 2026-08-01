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
    /// **The code is the identity.** It is canonical — one track, one code — so
    /// two people who build the same road independently arrive at the same
    /// entry, and re-importing something you already have is recognized rather
    /// than duplicated. There is no separate id to keep in step with it.
    ///
    /// The name and the dates live HERE, not in the code: a code carries
    /// content only, so a signature attests to the road rather than to what one
    /// device happens to call it.
    public struct Entry: Equatable, Sendable, Codable, Identifiable {
        /// The share code, **without any signature** — the road itself, so a
        /// signed and an unsigned share of one track are one entry. The signed
        /// code, when there is one, is kept alongside for re-sharing.
        public var id: String
        public var name: String
        /// The code as received, signature and all. `id` is its content half.
        public var code: String
        /// Who signed the code this entry was created from, if anyone, and
        /// whether it checked out **at that moment**.
        ///
        /// Cached rather than re-derived: the picker would otherwise verify on
        /// every render, which is the mistake the compile-per-frame slot made.
        public var authorKey: [UInt8]?
        public var signatureIsValid: Bool
        /// Whether this compiles into a raceable track — closed, valid, the lot.
        ///
        /// Cached, and for the same reason as the signature verdict: the picker
        /// asked `customTrack() != nil` per render, which COMPILED the layout
        /// every frame. Fine for one slot, O(n) compiles per frame for a library.
        public var isRaceable: Bool
        /// Made here. For an imported track this is when it arrived, since the
        /// author's own clock isn't something this device can know.
        public var createdAt: Date
        /// When it arrived from elsewhere; nil for one built here.
        public var importedAt: Date?
        /// Last edited here.
        public var updatedAt: Date

        public init(
            name: String, code: String, authorKey: [UInt8]? = nil,
            signatureIsValid: Bool = false, isRaceable: Bool = false, createdAt: Date,
            importedAt: Date? = nil, updatedAt: Date
        ) {
            self.id = TrackCode.contentCode(of: code)
            self.isRaceable = isRaceable
            self.name = name
            self.code = code
            self.authorKey = authorKey
            self.signatureIsValid = signatureIsValid
            self.createdAt = createdAt
            self.importedAt = importedAt
            self.updatedAt = updatedAt
        }

        /// The id a compiled `Track` races under. Hiscores key on this, so
        /// times follow the ROAD: renaming keeps them, and editing the track
        /// starts fresh — which is honest, since it is no longer the same road.
        public var trackID: String { id }

        /// Whether this entry came from somewhere else.
        public var isImported: Bool { importedAt != nil }
    }

    /// The tracks a race can actually start on, newest first.
    public var raceable: [Entry] { byRecency.filter(\.isRaceable) }

    /// Newest activity first — what a picker shows.
    public var byRecency: [Entry] {
        tracks.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func entry(id: String) -> Entry? {
        tracks.first { $0.id == id }
    }

    /// Whether this code is already in the library, signed or not.
    public func contains(code: String) -> Bool {
        entry(id: TrackCode.contentCode(of: code)) != nil
    }

    /// Add a track, or replace one with the same id.
    public mutating func put(_ entry: Entry) {
        if let index = tracks.firstIndex(where: { $0.id == entry.id }) {
            tracks[index] = entry
        } else {
            tracks.append(entry)
        }
    }

    public mutating func remove(id: String) {
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
        legacyCode: String?, into book: TrackLibraryBook, now: Date, name: String
    ) -> TrackLibraryBook {
        guard book.tracks.isEmpty, let legacyCode, !legacyCode.isEmpty else { return book }
        var migrated = book
        migrated.put(Entry(name: name, code: legacyCode, createdAt: now, updatedAt: now))
        return migrated
    }
}
