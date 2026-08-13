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
