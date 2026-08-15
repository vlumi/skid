import SkidCore
import SwiftUI

/// **Pick a track, by looking at it.**
///
/// Replaces a row of name chips, which was fine for four built-ins and useless the moment
/// a player had tracks of their own: "My track 3" says nothing about whether it is a tight
/// circuit or a long sweeper. Every row is drawn by the game's own renderer, so a preview
/// cannot disagree with the track it previews.
///
/// One list, two sections — the tracks that ship, and the tracks on this device. Sectioned
/// rather than mixed because they answer different questions ("what does this game have?"
/// versus "where is the one I made?"), and because only the second can be edited or
/// deleted.
struct TrackBrowserView: View {
    @ObservedObject var game: CouchGame
    let dismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(Text("Tracks", bundle: .module)) {
                        ForEach(TrackLibrary.builtins, id: \.id) { builtin in
                            tile(
                                id: builtin.id,
                                name: TrackLibrary.displayName(id: builtin.id),
                                layout: try? TrackCode.decode(builtin.code))
                        }
                    }

                    // Unfinished tracks are deliberately absent: the library keeps them,
                    // and offering one for a race would be offering a race that cannot
                    // start. They belong in the editor's own list.
                    if !game.library.raceable.isEmpty {
                        section(Text("Yours", bundle: .module)) {
                            ForEach(game.library.raceable) { entry in
                                tile(
                                    id: entry.trackID, name: entry.name,
                                    layout: try? TrackCode.decode(entry.code),
                                    signed: entry.signatureIsValid)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
                    .font(Retro.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Retro.panel)
                    .overlay(RetroBevel(thickness: 2))
                    .foregroundStyle(Retro.ink)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private func section(
        _ title: Text, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title
                .font(Retro.body)
                // On the ground, not on a panel — `ink` is dark-on-grey and vanishes here.
                .foregroundStyle(Retro.onGround)
            LazyVGrid(columns: columns, spacing: 12) { content() }
        }
    }

    /// **What this track holds** — the board, one line per tile.
    ///
    /// A record with a name reads "0:05.28 Ada"; a guest's reads as the bare time, which
    /// is honest (see `BestRecord.lapHolder`). A track nobody has raced says so rather
    /// than showing an empty row, so the blank means "unraced" instead of "broken".
    @ViewBuilder private func recordLine(for id: String, selected: Bool) -> some View {
        let best = game.hiscores.best(for: id)
        if let lap = best.bestLapTicks {
            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 7))
                Text(verbatim: formatTicks(lap))
                    .lineLimit(1)
                if let holder = best.lapHolder {
                    Text(verbatim: holder)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(0.75)
                }
            }
            .font(Retro.caption)
            .foregroundStyle(selected ? Retro.onHighlight : Retro.inkSoft)
        } else {
            Text("No time yet", bundle: .module)
                .font(Retro.caption)
                .foregroundStyle(selected ? Retro.onHighlight.opacity(0.7) : Retro.inkSoft)
        }
    }

    private func tile(
        id: String, name: String, layout: TrackLayout?, signed: Bool = false
    ) -> some View {
        let selected = game.trackID == id
        return Button {
            game.trackID = id
            dismiss()
        } label: {
            VStack(spacing: 6) {
                if let layout {
                    TrackThumbnail(layout: layout)
                        .frame(height: 96)
                } else {
                    // A code that will not decode shows as a blank rather than an error:
                    // one corrupt row is not worth a dialog, and the name still selects.
                    Rectangle()
                        .fill(Retro.panel.opacity(0.4))
                        .frame(height: 96)
                }
                HStack(spacing: 4) {
                    Text(verbatim: name)
                        .font(Retro.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if signed {
                        Image(systemName: "seal")
                            .font(Retro.caption)
                            .foregroundStyle(Retro.inkSoft)
                    }
                }
                .foregroundStyle(selected ? Retro.onHighlight : Retro.ink)
                recordLine(for: id, selected: selected)
            }
            .padding(6)
            .background(selected ? Retro.highlight : Retro.panel)
            .overlay(RetroBevel(thickness: 2))
        }
    }
}
