import Foundation

/// **One car in the race, and who is driving it.**
///
/// The whole field as one list, which is the point: player count and AI count used to
/// be two independent steppers that had to be kept consistent with each other and with
/// the grid's capacity. Three numbers, three chances to disagree — and they did (a solo
/// player's field was once silently cut to three AI while the grid showed nine slots).
///
/// As a list, the counts are *derived*. There is no way to ask for five humans and four
/// AI on a four-car grid, because the list is the field: its length is the field size,
/// and what each row says is what that car is.
/// **What kind of driver a row is** — the three-way choice on every row.
public enum DriverKind: String, Equatable, Sendable, Codable, CaseIterable {
    case guest
    case player
    case ai
}

public enum RaceEntrant: Equatable, Sendable, Codable, Identifiable {
    /// A person at this device who is not keeping records.
    case guest
    /// A person at this device with a profile.
    case profile(UUID)
    /// A computer driver at the given skill.
    case ai(AIDriver.Difficulty)

    /// Stable enough for a `ForEach` over a list that is edited in place.
    ///
    /// Deliberately NOT unique per row: two guests are genuinely the same thing, so
    /// their ids collide and `ForEach` needs the index as well. Named `id` only to
    /// satisfy `Identifiable` where the collection is keyed by something else.
    /// Which of the three segments this row shows as selected.
    public var kind: DriverKind {
        switch self {
        case .guest: return .guest
        case .profile: return .player
        case .ai: return .ai
        }
    }

    public var id: String {
        switch self {
        case .guest: return "guest"
        case .profile(let uuid): return "profile-\(uuid)"
        case .ai(let level): return "ai-\(level)"
        }
    }

    /// Whether a person at this device drives this car — the thing that decides how
    /// many control bands the screen is divided into.
    public var isHuman: Bool {
        switch self {
        case .guest, .profile: return true
        case .ai: return false
        }
    }

    /// The profile driving, if any. Nil for a guest *and* for AI, which is correct at
    /// every call site: both are "nobody to record against".
    public var profileID: UUID? {
        switch self {
        case .profile(let id): return id
        case .guest, .ai: return nil
        }
    }

    /// The seat identity this entrant presents, for the records layer. AI has none.
    public var seatIdentity: SeatIdentity? {
        switch self {
        case .guest: return .guest
        case .profile(let id): return .profile(id)
        case .ai: return nil
        }
    }
}

/// The field as a list, with the invariants that keep it raceable.
///
/// A free function rather than a type, because the list itself is the model — wrapping
/// it would add a layer whose only job is to forward `count`.
public enum RaceField {
    /// **Humans first, then AI**, because control bands are assigned to the first N cars
    /// in order — a human sitting behind an AI would be handed no band and no way to
    /// drive. Sorting maintains that invariant rather than merely asserting it, and is
    /// stable within each group so it never shuffles who is who.
    public static func ordered(_ entrants: [RaceEntrant]) -> [RaceEntrant] {
        entrants.filter(\.isHuman) + entrants.filter { !$0.isHuman }
    }

    /// How many people at this device are racing.
    public static func humanCount(_ entrants: [RaceEntrant]) -> Int {
        entrants.count(where: \.isHuman)
    }

    /// **The list never empties.** One human row is the floor, which is a legitimate
    /// race on its own: solo against the AI. There is no separate Solo mode to protect,
    /// because solo IS this list with one row.
    public static func nonEmpty(_ entrants: [RaceEntrant]) -> [RaceEntrant] {
        let ordered = ordered(entrants)
        guard humanCount(ordered) > 0 else { return [.guest] + ordered }
        return ordered
    }

    /// Trim to what the field can hold, keeping humans in preference to AI — losing
    /// somebody's seat to make room for a computer would be the wrong way round.
    public static func capped(_ entrants: [RaceEntrant], to capacity: Int) -> [RaceEntrant] {
        Array(ordered(entrants).prefix(max(1, capacity)))
    }
}

extension Sequence {
    /// `count(where:)` is Swift 6.0; this keeps the call sites readable on 5.9.
    fileprivate func count(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
