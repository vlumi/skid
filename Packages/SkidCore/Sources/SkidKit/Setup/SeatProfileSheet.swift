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
struct SeatProfileSheet: View {
    @ObservedObject var game: CouchGame
    /// The row being edited — an index into `game.entrants`.
    let seat: Int
    let dismiss: () -> Void

    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(
                        title: Text("Guest", bundle: .module),
                        subtitle: Text("Race without keeping results", bundle: .module),
                        selected: game.entrants.indices.contains(seat)
                            && game.entrants[seat].kind != .player
                    ) {
                        game.setEntrant(.guest, at: seat)
                        dismiss()
                    }
                }

                if !game.profiles.profiles.isEmpty {
                    Section {
                        // Recency order, so whoever plays on this phone is at the top
                        // rather than whoever registered first.
                        ForEach(game.profiles.byRecency) { profile in
                            row(
                                title: Text(verbatim: profile.name),
                                subtitle: nil,
                                selected: game.entrants.indices.contains(seat)
                                    && game.entrants[seat].profileID == profile.id,
                                color: CouchGame.palette[
                                    profile.colorIndex % CouchGame.palette.count]
                            ) {
                                game.setEntrant(.profile(profile.id), at: seat)
                                dismiss()
                            }
                        }
                        .onDelete { offsets in
                            let ordered = game.profiles.byRecency
                            for index in offsets where ordered.indices.contains(index) {
                                game.deleteProfile(id: ordered[index].id)
                            }
                        }
                    } header: {
                        Text("On this device", bundle: .module)
                    }
                }

                Section {
                    HStack {
                        TextField(
                            String(localized: "Name", bundle: .module), text: $newName
                        )
                        .nameFieldStyle()
                        .onSubmit(create)
                        Button {
                            create()
                        } label: {
                            Text("Add", bundle: .module)
                        }
                        // Nothing to add from whitespace — and `cleaned` is the same
                        // rule the model applies, so the button cannot promise
                        // something the model then refuses.
                        .disabled(PlayerProfile.cleaned(name: newName) == nil)
                    }
                } header: {
                    Text("New player", bundle: .module)
                } footer: {
                    if game.profiles.profiles.count >= ProfileBook.maxProfiles {
                        Text("No room for another player. Delete one first.", bundle: .module)
                    } else {
                        Text(
                            "A named player keeps their best times. Guests do not.",
                            bundle: .module)
                    }
                }
            }
            .navigationTitle(Text("Player \(seat + 1)", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
        }
    }

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

    private func row(
        title: Text, subtitle: Text?, selected: Bool, color: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let color {
                    Circle().fill(color).frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    title.foregroundStyle(.primary)
                    if let subtitle {
                        subtitle.font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }
}
