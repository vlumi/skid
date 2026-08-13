import Foundation

/// **Who is driving — for the people who want to be remembered.**
///
/// A name and a preferred color, stored on this device. Not an account: no sign-in,
/// no server, nothing that leaves the phone.
///
/// **A seat does not need one.** Guests are the default and race exactly like anyone
/// else (see `ProfileBook`), because asking for a name before the first race would put
/// a text field in front of the thing people opened the app for — and a visitor taking
/// one turn on someone else's couch should not have to register for it. What a profile
/// buys is *continuity*: your times kept, your name in the standings, your color
/// remembered.
public struct PlayerProfile: Equatable, Sendable, Codable, Identifiable {
    /// Stable identity, so a rename does not orphan the records keyed to it.
    ///
    /// A UUID rather than the name for exactly that reason: names are the part people
    /// change, and "best lap" belongs to a person rather than to a spelling.
    public var id: UUID
    /// What the standings show. Not unique — two people called Sam on one couch is
    /// their problem to solve, and refusing the second one would be worse.
    public var name: String
    /// Preferred car color, as an index into `CarPalette.paints`.
    ///
    /// A *preference*, not a reservation: a race assigns colors so the whole field
    /// stays distinguishable, and two profiles wanting seat 3's blue cannot both have
    /// it. Stored as an index rather than a color so the palette can be re-tuned
    /// without rewriting everyone's profile.
    public var colorIndex: Int
    public var createdAt: Date
    /// When this profile last took a seat. What a "recently played" ordering reads, so
    /// the people who actually use this phone come first.
    public var lastPlayedAt: Date?

    public init(
        id: UUID = UUID(), name: String, colorIndex: Int,
        createdAt: Date = Date(), lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.createdAt = createdAt
        self.lastPlayedAt = lastPlayedAt
    }

    /// Longest name worth storing. Generous for a real name, short enough that a
    /// standings row cannot be pushed off the screen by one.
    public static let maxNameLength = 16

    /// A name with the surrounding space removed and the length capped — nil when
    /// nothing usable is left.
    ///
    /// Returning nil rather than a placeholder is deliberate: "  " is not a name, and
    /// the caller's answer to that is *stay a guest*, which needs no invented text.
    public static func cleaned(name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }
}

/// **Every profile on this device, and the rule that guests come free.**
///
/// The `HiscoreBook` shape exactly — a versioned envelope with a tolerant decode — so
/// a future format cannot eat existing profiles: an unknown version decodes to nil and
/// the caller starts fresh rather than crashing.
public struct ProfileBook: Equatable, Sendable, Codable {
    public static let currentVersion = 1

    public var version = ProfileBook.currentVersion
    public var profiles: [PlayerProfile] = []

    public init() {}

    /// **How many profiles one device may hold.**
    ///
    /// Not a technical limit — this is a couch, and a phone that has been handed
    /// around a party should not accumulate a hundred one-race identities. Guests
    /// exist precisely so the casual case costs nothing, and a cap keeps the picker a
    /// list you can read rather than one you have to search.
    public static let maxProfiles = 12

    public func profile(id: UUID) -> PlayerProfile? {
        profiles.first { $0.id == id }
    }

    /// Newest-played first, then newest-created — so the people who use this phone
    /// are at the top of a picker and a brand-new profile is not buried.
    public var byRecency: [PlayerProfile] {
        profiles.sorted {
            ($0.lastPlayedAt ?? $0.createdAt, $0.createdAt)
                > ($1.lastPlayedAt ?? $1.createdAt, $1.createdAt)
        }
    }

    /// Add or replace, keyed by id. Returns false when the book is full and this
    /// would be a new entry — updating an existing profile always succeeds.
    @discardableResult
    public mutating func put(_ profile: PlayerProfile) -> Bool {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            return true
        }
        guard profiles.count < Self.maxProfiles else { return false }
        profiles.append(profile)
        return true
    }

    public mutating func remove(id: UUID) {
        profiles.removeAll { $0.id == id }
    }

    /// Note that this profile just played, for the recency ordering.
    public mutating func markPlayed(id: UUID, at when: Date = Date()) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].lastPlayedAt = when
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Tolerant decode: nil on anything this build cannot read, so a newer format is
    /// a fresh start rather than a crash.
    public static func decode(_ data: Data) -> ProfileBook? {
        guard let book = try? JSONDecoder().decode(ProfileBook.self, from: data),
            book.version <= currentVersion
        else { return nil }
        return book
    }
}

/// **Who is in a seat**, which is a profile or nobody in particular.
///
/// The two cases are the whole identity model: a seat either belongs to someone who
/// wants to be remembered, or it is a guest — and a guest is not a lesser player, only
/// an anonymous one. Racing is identical either way; the difference is whether there is
/// anywhere to write the result.
public enum SeatIdentity: Equatable, Sendable, Codable {
    case guest
    case profile(UUID)

    /// The profile's id, or nil for a guest. Named for how it reads at the call site:
    /// `guard let id = seat.profileID else { return }` is the shape of every
    /// record-keeping path, since a guest has nothing to record against.
    public var profileID: UUID? {
        switch self {
        case .guest: return nil
        case .profile(let id): return id
        }
    }
}
