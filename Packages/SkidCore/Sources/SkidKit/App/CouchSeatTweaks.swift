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

    /// Cycle one player's color to the next not held by another RACING seat —
    /// the fast gesture. `chooseColor` is the deliberate one.
    public func cycleColor(slot: Int) {
        guard colorIndices.indices.contains(slot) else { return }
        let taken = colorsTaken(besides: slot)
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

    /// Take a color outright — the palette sheet's pick, where the player can
    /// see the whole nine and choose across the ring instead of walking it.
    ///
    /// Refuses a color another racing seat holds, rather than trusting the view
    /// to have disabled that chip: the invariant is "no two racing seats alike",
    /// and a rule enforced only in a view is a rule the next view breaks.
    public func chooseColor(_ color: Int, slot: Int) {
        guard colorIndices.indices.contains(slot), (0..<Self.palette.count).contains(color),
            !colorsTaken(besides: slot).contains(color)
        else { return }
        assignColor(color, to: slot)
        rememberColorPreference(slot: slot)
    }

    /// The colors the RACING seats hold, excluding one seat's own.
    ///
    /// Only the seats actually in the race block a color. `colorIndices` covers
    /// the whole nine-slot grid and defaults to all nine palette colors, so
    /// counting every slot left exactly one "free" color — the asking seat's own
    /// — and cycling stood still. Reported as friction: the picker existed and
    /// did nothing.
    func colorsTaken(besides slot: Int) -> Set<Int> {
        Set(
            colorIndices.prefix(max(1, playerCount)).enumerated()
                .filter { $0.offset != slot }.map(\.element))
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
        assignColor(
            CarPalette.claim(preferred: preferred, taken: colorsTaken(besides: slot)),
            to: slot)
    }
}
