import SkidCore
import SwiftUI

/// **Who is racing — the first thing the app asks, and the only thing this screen is.**
///
/// One list, grown by three add buttons. What replaced what, and why:
///
/// - **No player count and no AI count.** They were two steppers that had to agree with
///   each other and with the grid's capacity; three numbers meant three chances to
///   disagree, and they once did (a solo field silently cut to three AI). The list *is*
///   the field, so both counts are derived and cannot contradict it.
/// - **No Solo/Couch choice.** Solo is this list with one row. A door that set a count
///   the list could immediately contradict was a distinction without a difference.
/// - **No seating-layout picker.** Two players are face-to-face; three get a fixed
///   corner. Both were questions a player had no basis to answer before driving.
/// - **No AI rows.** AI was briefly a third kind of row, and it brought four special
///   rules with it that existed for no other reason: row 0 could not be AI, humans had to
///   sort ahead of AI, AI could not travel to a nearby race, and hosting with AI was
///   never plumbed. It is a property of the race now — fill the grid or do not — which is
///   where it belonged, since a computer is not "who is here".
///
/// **A row is one tap**, opening a picker whose first entry is Guest — so both answers
/// live in one place. Each row remembers the profile it last held, so a row that goes
/// back to Guest and then to a player again does not have to be told twice.
struct PlayerListView: View {
    @ObservedObject var game: CouchGame
    /// Which row's player picker is open.
    @State private var pickingFor: Int?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(game.entrants.enumerated()), id: \.offset) { index, entrant in
                row(index: index, entrant: entrant)
            }
            addButtons
        }
        .sheet(
            isPresented: Binding(
                get: { pickingFor != nil },
                set: { if !$0 { pickingFor = nil } })
        ) {
            SeatProfileSheet(game: game, seat: pickingFor ?? 0) { pickingFor = nil }
        }
    }

    /// **The whole row is one button, and it opens the picker.**
    ///
    /// There was briefly a segmented Guest/Player toggle here. With AI gone from the list
    /// that leaves a two-way switch, and a segmented control for a binary choice is more
    /// chrome than the choice deserves — especially since the picker's first row IS
    /// "Guest", so it already covers both answers. One tap, one surface.
    private func row(index: Int, entrant: RaceEntrant) -> some View {
        HStack(spacing: 12) {
            // The car's color, so the list reads as the grid rather than as settings.
            Circle()
                .fill(CouchGame.palette[game.colorIndices[index % game.colorIndices.count]])
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))

            Button {
                pickingFor = index
            } label: {
                HStack(spacing: 8) {
                    Text(verbatim: game.entrantDetail(index))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    // Says which of the two this is without a control to read it off.
                    if entrant.kind == .guest {
                        Text("Guest", bundle: .module)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            // Never below one row, so this is absent rather than disabled on the last
            // one — a control that cannot work should not be there to press.
            if game.entrants.count > 1 {
                Button {
                    game.removeEntrant(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.white.opacity(0.55))
                        .font(.title3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Two ways to add a person: anonymously, or by name. Both add a row — the second
    /// then opens the picker, since a row has to exist before somebody can be put in it.
    private var addButtons: some View {
        HStack(spacing: 8) {
            add(Text("+ Guest", bundle: .module), kind: .guest) {
                game.addEntrant(.guest)
            }
            add(Text("+ Player", bundle: .module), kind: .player) {
                if game.addEntrant(.guest) { pickingFor = game.entrants.count - 1 }
            }
        }
    }

    private func add(_ title: Text, kind: DriverKind, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            title
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.white.opacity(0.16), in: Capsule())
                .foregroundStyle(.white)
        }
        .disabled(!game.canAdd(kind))
        .opacity(game.canAdd(kind) ? 1 : 0.35)
    }
}
