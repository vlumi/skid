import SkidCore
import SwiftUI

/// Per-seat setup tweaks — split from `CouchGame.swift` on the file-length
/// budget.
extension CouchGame {
    /// Toggle one player's control scheme (Casual ↔ Pro).
    public func toggleScheme(slot: Int) {
        guard schemes.indices.contains(slot) else { return }
        schemes[slot] = schemes[slot] == .casual ? .pro : .casual
    }

    /// Cycle one player's color to the next not held by another RACING seat.
    ///
    /// Only the seats actually in the race block a color. The slots array covers
    /// the whole grid and defaults to all nine palette colors, so counting every
    /// slot as taken left exactly one "free" color — the tapper's own — and the
    /// button cycled in place. Reported as friction: the picker existed and did
    /// nothing.
    public func cycleColor(slot: Int) {
        guard colorIndices.indices.contains(slot) else { return }
        let racing = max(1, playerCount)
        let taken = Set(
            colorIndices.prefix(racing).enumerated()
                .filter { $0.offset != slot }.map(\.element))
        var next = colorIndices[slot]
        repeat {
            next = (next + 1) % Self.palette.count
        } while taken.contains(next)
        assignColor(next, to: slot)
        // An explicit pick becomes the profile's preference. Seeding does NOT
        // come through here — a preference bumped by one crowded race must not
        // overwrite what the player actually chose.
        rememberColorPreference(slot: slot)
    }

    /// Give a seat a color, keeping `colorIndices` a permutation of the palette:
    /// whichever idle slot held the color takes the old one in exchange. Without
    /// the swap two slots share a color, and the duplicate surfaces the moment a
    /// player is added into the idle one.
    func assignColor(_ color: Int, to slot: Int) {
        guard colorIndices.indices.contains(slot), colorIndices[slot] != color else { return }
        var next = colorIndices
        if let holder = next.firstIndex(of: color) {
            next[holder] = next[slot]
        }
        next[slot] = color
        colorIndices = next
    }

    /// A profile in this seat keeps the pick as its preference — it is what the
    /// seat seeds from next time, and what travels to a networked lobby as this
    /// player's claim.
    private func rememberColorPreference(slot: Int) {
        guard entrants.indices.contains(slot),
            let id = entrants[slot].profileID,
            var profile = profiles.profile(id: id),
            profile.colorIndex != colorIndices[slot]
        else { return }
        profile.colorIndex = colorIndices[slot]
        update(profile)
    }

    /// Seed a seat's color from a profile's preference, claimed first-come
    /// against the seats already racing (`CarPalette.claim`) — the same rule a
    /// networked lobby applies, so what you see at home is what a host grants.
    func seedColor(fromProfile id: UUID, at slot: Int) {
        guard let preferred = profiles.profile(id: id)?.colorIndex,
            colorIndices.indices.contains(slot)
        else { return }
        let racing = max(1, playerCount)
        let taken = Set(
            colorIndices.prefix(racing).enumerated()
                .filter { $0.offset != slot }.map(\.element))
        assignColor(CarPalette.claim(preferred: preferred, taken: taken), to: slot)
    }
}
