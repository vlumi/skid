import SkidCore
import SwiftUI

/// **Who is playing, seat by seat.**
///
/// Split out of `CouchGame` for the file-length limit, and it is a coherent subject on
/// its own: the rules about guests live here.
///
/// The governing decision is that **a guest is the default and a profile is an
/// upgrade**. Nothing in this file can fail in a way that stops somebody racing —
/// assigning a profile to a seat is the only thing that ever needs to succeed, and a
/// seat with no profile is a valid, complete answer.
extension CouchGame {
    /// The profile in a seat, or nil for a guest.
    public func profile(inSeat seat: Int) -> PlayerProfile? {
        guard let id = identity(inSeat: seat).profileID else { return nil }
        return profiles.profile(id: id)
    }

    /// Who is in a seat. Out-of-range seats read as guests rather than trapping: the
    /// caller is a view laying out however many bands the rig has, and a crash is a
    /// worse answer than "nobody in particular".
    public func identity(inSeat seat: Int) -> SeatIdentity {
        guard seatIdentities.indices.contains(seat) else { return .guest }
        return seatIdentities[seat]
    }

    /// What to show for a seat: the profile's name, or the seat's own label.
    ///
    /// **"P2" is not a placeholder waiting to be filled in** — it is what a guest is
    /// called, and it is enough. A guest on a couch already knows which car is theirs
    /// from where they are sitting.
    public func displayName(forSeat seat: Int) -> String {
        profile(inSeat: seat)?.name ?? "P\(seat + 1)"
    }

    /// Put a profile in a seat — or `.guest` to vacate it.
    ///
    /// **Exclusive**: taking a seat releases any other seat the same profile held, so
    /// one person cannot drive two cars. Without this, picking your own name in seat 2
    /// after having been in seat 1 would enter you twice and file both cars' results
    /// against you.
    public func assign(_ identity: SeatIdentity, toSeat seat: Int) {
        guard seatIdentities.indices.contains(seat) else { return }
        if let id = identity.profileID {
            for other in seatIdentities.indices where other != seat {
                if seatIdentities[other].profileID == id { seatIdentities[other] = .guest }
            }
        }
        seatIdentities[seat] = identity
    }

    /// Create a profile and put it straight into `seat`, since that is invariably why
    /// somebody is typing a name. Returns nil when the name is unusable or the book is
    /// full — in both cases the seat is untouched and stays a guest, which is a working
    /// outcome rather than an error state.
    @discardableResult
    public func createProfile(named name: String, colorIndex: Int, forSeat seat: Int)
        -> PlayerProfile?
    {
        guard let cleaned = PlayerProfile.cleaned(name: name) else { return nil }
        let profile = PlayerProfile(name: cleaned, colorIndex: colorIndex)
        var book = profiles
        guard book.put(profile) else { return nil }
        profiles = book
        saveProfiles()
        assign(.profile(profile.id), toSeat: seat)
        return profile
    }

    /// Rename, or change the preferred color. Silently ignores an unknown id, so a
    /// stale view cannot resurrect a deleted profile.
    public func update(_ profile: PlayerProfile) {
        guard profiles.profile(id: profile.id) != nil else { return }
        var book = profiles
        _ = book.put(profile)
        profiles = book
        saveProfiles()
    }

    /// Delete a profile, and vacate any seat holding it.
    ///
    /// **Records are deliberately left behind.** They are keyed by profile id, so
    /// deleting the profile orphans them rather than erasing them — which is the
    /// forgiving order of operations if somebody deletes the wrong row, and costs a
    /// few bytes until a cleanup pass exists.
    public func deleteProfile(id: UUID) {
        var book = profiles
        book.remove(id: id)
        profiles = book
        saveProfiles()
        for seat in seatIdentities.indices where seatIdentities[seat].profileID == id {
            seatIdentities[seat] = .guest
        }
    }

    /// Note that everyone seated has just played, for the recency ordering that puts
    /// this phone's regulars at the top of the picker. Guests are skipped: there is
    /// nothing to mark.
    public func markSeatedProfilesPlayed() {
        var book = profiles
        var changed = false
        for seat in 0..<playerCount {
            guard let id = identity(inSeat: seat).profileID else { continue }
            book.markPlayed(id: id)
            changed = true
        }
        guard changed else { return }
        profiles = book
        saveProfiles()
    }

    func loadProfiles() {
        profiles = profileFile.load()
    }

    func saveProfiles() {
        profileFile.save(profiles)
    }
}

// MARK: - The field as a list

/// **Who is racing, as one list rather than two counts.**
///
/// `playerCount` and `aiCount` survive as *derived* properties so the rest of the app
/// keeps working unchanged, but nothing stores them any more: the list is the field.
extension CouchGame {
    /// How many people are playing on this device, 1…`maxLocalPlayers`.
    public var playerCount: Int {
        get { max(1, RaceField.humanCount(entrants)) }
        set { setHumanCount(newValue) }
    }

    /// How many AI cars fill the rest of the field, 0…(`maxCars` − players).
    public var aiCount: Int {
        get { entrants.filter { !$0.isHuman }.count }
        set { setAICount(newValue) }
    }

    /// Add or remove human rows to reach `count`. Growing adds guests, since a new row
    /// belongs to whoever just sat down and they have not said who they are yet;
    /// shrinking drops the last ones, so the person who left stops racing.
    func setHumanCount(_ count: Int) {
        let target = max(1, min(Self.maxLocalPlayers, count))
        var humans = entrants.filter(\.isHuman)
        let ai = entrants.filter { !$0.isHuman }
        while humans.count < target { humans.append(.guest) }
        if humans.count > target { humans.removeLast(humans.count - target) }
        // Taking a seat evicts an AI rather than overfilling the grid.
        entrants = humans + ai.prefix(max(0, Self.maxCars - humans.count))
        syncSeatIdentities()
    }

    /// Replace the AI rows so there are `count` of them, at the current difficulty.
    func setAICount(_ count: Int) {
        let humans = entrants.filter(\.isHuman)
        let target = max(0, min(Self.maxCars - humans.count, count))
        entrants = humans + Array(repeating: .ai(aiDifficulty), count: target)
        syncSeatIdentities()
    }

    /// What a row shows next to its toggle.
    public func entrantDetail(_ index: Int) -> String {
        guard entrants.indices.contains(index) else { return "" }
        switch entrants[index] {
        case .guest:
            return "P\(index + 1)"
        case .profile(let id):
            return profiles.profile(id: id)?.name ?? "P\(index + 1)"
        case .ai(let level):
            return String(describing: level).capitalized
        }
    }

    /// **Switch a row between guest, a named player, and AI — one tap.**
    ///
    /// The player case is *sticky*: each row remembers the profile it last held, so
    /// cycling away to AI and back returns the same person rather than asking again.
    /// Returns false when a row wants a player and has none to return to — the caller
    /// then shows the picker, which is the only case that needs a modal.
    @discardableResult
    public func setKind(_ kind: DriverKind, at index: Int) -> Bool {
        guard entrants.indices.contains(index) else { return true }
        switch kind {
        case .guest:
            setEntrant(.guest, at: index)
        case .ai:
            setEntrant(.ai(aiDifficulty), at: index)
        case .player:
            // Only if that profile still exists and is not already driving.
            guard let id = rememberedProfiles[index], profiles.profile(id: id) != nil,
                !entrants.enumerated().contains(where: {
                    $0.offset != index && $0.element.profileID == id
                })
            else {
                return false
            }
            setEntrant(.profile(id), at: index)
        }
        return true
    }

    /// Change one row, keeping humans ahead of AI so the control bands still line up
    /// with the people expecting them.
    public func setEntrant(_ entrant: RaceEntrant, at index: Int) {
        guard entrants.indices.contains(index) else { return }
        var next = entrants
        next[index] = entrant
        // A profile may only drive one car, exactly as with seats.
        if let id = entrant.profileID {
            for other in next.indices where other != index && next[other].profileID == id {
                next[other] = .guest
            }
            rememberedProfiles[index] = id
        }
        entrants = RaceField.nonEmpty(RaceField.capped(next, to: Self.maxCars))
        syncSeatIdentities()
    }

    /// Whether another row of this kind would be accepted, so a view can disable a
    /// button rather than offer a tap that does nothing.
    public func canAdd(_ kind: DriverKind) -> Bool {
        guard entrants.count < Self.maxCars else { return false }
        guard kind != .ai else { return true }
        return RaceField.humanCount(entrants) < Self.maxLocalPlayers
    }

    @discardableResult
    public func addEntrant(_ entrant: RaceEntrant) -> Bool {
        guard canAdd(entrant.kind) else { return false }
        entrants = RaceField.ordered(entrants + [entrant])
        if let id = entrant.profileID, let row = entrants.lastIndex(of: entrant) {
            rememberedProfiles[row] = id
        }
        syncSeatIdentities()
        return true
    }

    /// Remove a row. Never leaves the list without a person in it.
    public func removeEntrant(at index: Int) {
        guard entrants.indices.contains(index), entrants.count > 1 else { return }
        var next = entrants
        next.remove(at: index)
        rememberedProfiles.removeValue(forKey: index)
        entrants = RaceField.nonEmpty(next)
        syncSeatIdentities()
    }

    /// Mirror the list's human rows onto `seatIdentities`, which the records layer and
    /// the race chrome read. Kept in step here rather than derived on demand so the
    /// existing seat API keeps working unchanged.
    func syncSeatIdentities() {
        var identities = Array(repeating: SeatIdentity.guest, count: Self.maxLocalPlayers)
        for (seat, entrant) in entrants.filter(\.isHuman).enumerated()
        where seat < identities.count {
            identities[seat] = entrant.seatIdentity ?? .guest
        }
        seatIdentities = identities
    }
}
