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
///
/// **Switching a row is one tap**, because filling a grid should not need a dropdown per
/// car. Choosing *which* named player is the exception and opens a picker — and each row
/// remembers the profile it last held, so switching away to AI and back does not ask
/// again.
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

    private func row(index: Int, entrant: RaceEntrant) -> some View {
        HStack(spacing: 10) {
            // The car's color, so the list reads as the grid rather than as settings.
            Circle()
                .fill(CouchGame.palette[game.colorIndices[index % game.colorIndices.count]])
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))

            kindToggle(index: index, entrant: entrant)

            // Tapping the detail opens the picker for a player row, and is where the
            // AI's level will go when it becomes per-row.
            Button {
                if entrant.kind == .player { pickingFor = index }
            } label: {
                Text(verbatim: game.entrantDetail(index))
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(entrant.kind != .player)

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
        .padding(.vertical, 8)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Guest / Player / AI, as three segments rather than a cycle — a cycle makes you
    /// tap through states you do not want to reach the one you do.
    private func kindToggle(index: Int, entrant: RaceEntrant) -> some View {
        HStack(spacing: 0) {
            ForEach(DriverKind.allCases, id: \.self) { kind in
                let selected = entrant.kind == kind
                // The first row is always a person — see `setKind`. Dimmed rather than
                // hidden, so the toggle keeps the same shape on every row.
                let allowed = !(index == 0 && kind == .ai)
                Button {
                    // A player row with nobody remembered needs the picker; every other
                    // switch is immediate.
                    if !game.setKind(kind, at: index) { pickingFor = index }
                } label: {
                    label(for: kind)
                        .font(.caption2.bold())
                        .frame(width: 46, height: 28)
                        .background(selected ? .white.opacity(0.9) : .clear)
                        .foregroundStyle(selected ? .black : .white.opacity(allowed ? 0.75 : 0.3))
                }
                .disabled(!allowed)
            }
        }
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func label(for kind: DriverKind) -> Text {
        switch kind {
        case .guest: return Text("Guest", bundle: .module)
        case .player: return Text("Player", bundle: .module)
        case .ai: return Text("AI", bundle: .module)
        }
    }

    /// **Three add buttons, not one.** Adding is where speed matters — filling a grid
    /// should be one tap per car — so the kind is chosen as you add rather than by
    /// adding a row and then changing it.
    private var addButtons: some View {
        HStack(spacing: 8) {
            add(Text("+ Guest", bundle: .module), kind: .guest) {
                game.addEntrant(.guest)
            }
            add(Text("+ Player", bundle: .module), kind: .player) {
                // Adds a guest row and opens the picker on it: the row has to exist
                // before somebody can be put in it.
                if game.addEntrant(.guest) { pickingFor = game.entrants.count - 1 }
            }
            add(Text("+ AI", bundle: .module), kind: .ai) {
                game.addEntrant(.ai(game.aiDifficulty))
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
