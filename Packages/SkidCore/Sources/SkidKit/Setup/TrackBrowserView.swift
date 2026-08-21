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
    /// **Where the choice goes.** Nil means the browser is picking the track for
    /// the next race and writes `game.trackID` — the original behaviour. A
    /// tournament passes a handler instead, so the same browser (thumbnails,
    /// sections, signing marks and all) can fill a slot in a series line-up
    /// rather than needing a second, drifting copy of itself.
    var choose: ((String) -> Void)?
    /// Which id reads as selected. Defaults to the race's track.
    var selectedID: String?

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
    /// **What the track is**, so choosing one is not guesswork from a thumbnail:
    /// how long a lap is, how many corners, and whether it climbs. The same
    /// numbers the editor shows while building (`TrackStats`), which is what
    /// makes a deliberate spread across the library visible.
    @ViewBuilder private func statsLine(layout: TrackLayout?, selected: Bool) -> some View {
        if let layout, let stats = TrackStats.of(layout: layout) {
            // A tile is narrow, so this is the short form — but still words
            // rather than glyphs: "4 corners" needs no legend, where "4⌒" does.
            // The climb is named only when there is one, which is the whole
            // point of showing it.
            Text(verbatim: tileSummary(stats))
                .font(.system(size: 9).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Retro.onHighlight.opacity(0.8) : Retro.inkSoft)
        }
    }

    /// The tile's one-line summary: how long, how many corners, and whether it
    /// climbs. Assembled as a string rather than a row of views so it can shrink
    /// to fit a narrow tile as one piece.
    private func tileSummary(_ stats: TrackStats) -> String {
        var parts = [
            WorldScale.distanceLabel(units: stats.length), "\(stats.corners) corners",
        ]
        if stats.topLevel > 0 { parts.append("\(stats.topLevel) up") }
        return parts.joined(separator: " · ")
    }

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
        let selected = (selectedID ?? game.trackID) == id
        return Button {
            if let choose {
                choose(id)
            } else {
                game.trackID = id
            }
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
                statsLine(layout: layout, selected: selected)
                recordLine(for: id, selected: selected)
            }
            .padding(6)
            .background(selected ? Retro.highlight : Retro.panel)
            .overlay(RetroBevel(thickness: 2))
        }
    }
}
