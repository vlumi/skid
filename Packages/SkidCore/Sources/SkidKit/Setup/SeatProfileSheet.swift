import SkidCore
import SwiftUI

/// **Claiming a row: pick a name, make one, or stay a guest.**
///
/// Reached from a row's Player segment in `PlayerListView`. Deliberately reachable
/// rather than compulsory — every path out of here is valid, including the one that
/// changes nothing, because a guest is a complete answer.
///
/// **Writes to `entrants`, not to `seatIdentities`.** Those were briefly two parallel
/// models: the picker set the seat while the list read the row, so choosing a player
/// left the row showing Guest. The list is the single truth and seats derive from it.
///
/// The ordering is the argument: **Guest first**, then the people who use this phone
/// (most recently played first), then making a new one. A picker that led with a text
/// field would be asking everyone to register.
///
/// Drawn in `Retro` rather than as a `List`: this was the last native `NavigationStack`
/// in the app, and a stock iOS sheet in the middle of a 90s menu was the one screen that
/// still looked borrowed.
struct SeatProfileSheet: View {
    @ObservedObject var game: CouchGame
    /// The row being edited — an index into `game.entrants`.
    let seat: Int
    let dismiss: () -> Void

    @State private var newName = ""

    private var isGuest: Bool {
        game.entrants.indices.contains(seat) && game.entrants[seat].kind != .player
    }

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    retroLeaveRow(retroClose(dismiss)).padding(.horizontal, -16)
                    RetroTitle(Text("Player \(seat + 1)", bundle: .module))
                    guestPanel
                    if !game.profiles.profiles.isEmpty { peoplePanel }
                    newPlayerPanel
                }
                .padding(16)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }

        }
    }

    private var guestPanel: some View {
        VStack(spacing: 8) {
            RetroHeading(Text("ANYONE", bundle: .module))
            RetroChoice(
                label: Text("Guest", bundle: .module),
                detail: Text("Race without keeping results", bundle: .module),
                selected: isGuest
            ) {
                game.setEntrant(.guest, at: seat)
                dismiss()
            }
        }
        .retroPanel()
    }

    private var peoplePanel: some View {
        VStack(spacing: 8) {
            RetroHeading(Text("ON THIS DEVICE", bundle: .module))
            // Recency order, so whoever plays on this phone is at the top rather than
            // whoever registered first.
            ForEach(game.profiles.byRecency) { profile in
                let selected =
                    game.entrants.indices.contains(seat)
                    && game.entrants[seat].profileID == profile.id
                HStack(spacing: 8) {
                    RetroChoice(
                        label: Text(verbatim: profile.name),
                        selected: selected,
                        swatch: CouchGame.palette[
                            profile.colorIndex % CouchGame.palette.count]
                    ) {
                        game.setEntrant(.profile(profile.id), at: seat)
                        dismiss()
                    }
                    // Swipe-to-delete went with the `List`. An explicit button is
                    // better here anyway: this is a menu, not a mail inbox, and a
                    // hidden gesture is not something a player will find.
                    Button {
                        game.deleteProfile(id: profile.id)
                    } label: {
                        Text(verbatim: "✕")
                            .font(Retro.body)
                            .foregroundStyle(Retro.danger)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Delete \(profile.name)", bundle: .module))
                }
            }
        }
        .retroPanel()
    }

    private var newPlayerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            RetroHeading(Text("NEW PLAYER", bundle: .module))
            HStack(spacing: 8) {
                TextField(String(localized: "Name", bundle: .module), text: $newName)
                    .nameFieldStyle()
                    .font(Retro.body)
                    .foregroundStyle(Retro.ink)
                    .onSubmit(create)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 40)
                    .background(Retro.panel.opacity(0.55))
                    .overlay(RetroBevel(inset: true, thickness: 2))
                Button(action: create) {
                    Text("ADD", bundle: .module)
                        .font(Retro.body)
                        .foregroundStyle(canAdd ? Retro.onHighlight : Retro.inkSoft)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(canAdd ? Retro.highlight : Retro.panel.opacity(0.5))
                        .overlay(RetroBevel(inset: !canAdd, thickness: 2))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
            if game.profiles.profiles.count >= ProfileBook.maxProfiles {
                Text("No room for another player. Delete one first.", bundle: .module)
                    .font(Retro.caption)
                    .foregroundStyle(Retro.danger)
            } else {
                Text("A named player keeps their best times. Guests do not.", bundle: .module)
                    .font(Retro.caption)
                    .foregroundStyle(Retro.inkSoft)
            }
        }
        .retroPanel()
    }

    /// Nothing to add from whitespace — and `cleaned` is the same rule the model
    /// applies, so the button cannot promise something the model then refuses.
    private var canAdd: Bool { PlayerProfile.cleaned(name: newName) != nil }

    private func create() {
        // The seat's own color is the sensible default preference: it is the car this
        // person is about to drive, and picking a color is a separate decision.
        let color = game.colorIndices.indices.contains(seat) ? game.colorIndices[seat] : 0
        guard game.createProfile(named: newName, colorIndex: color, forSeat: seat) != nil else {
            return
        }
        newName = ""
        dismiss()
    }
}
