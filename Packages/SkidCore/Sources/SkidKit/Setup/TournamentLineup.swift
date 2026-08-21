import SkidCore
import SwiftUI

/// **The series line-up: four races, and which track each one runs.**
///
/// Answers all three of "pick manually, or randomly, or change a random pick"
/// with one surface rather than three: the list arrives drawn, `Redraw` deals a
/// fresh one, and tapping any row opens the track browser for that race. Manual
/// picking is just swapping every row.
struct TournamentLineup: View {
    @ObservedObject var game: CouchGame
    /// Which race's track is being changed — an index into the line-up.
    @State private var choosingFor: Int?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Line-up", bundle: .module)
                    .font(Retro.heading)
                    .foregroundStyle(Retro.inkSoft)
                Spacer()
                Button {
                    game.drawTournamentTracks()
                } label: {
                    Text("Redraw", bundle: .module)
                        .font(Retro.caption)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(Retro.panel)
                        .overlay(RetroBevel(thickness: 2))
                        .foregroundStyle(Retro.ink)
                }
                .buttonStyle(.plain)
            }
            let lineup = Array(game.pendingTournamentTracks.enumerated())
            ForEach(lineup, id: \.offset) { entry in
                row(index: entry.offset, id: entry.element)
            }
            // The pool is built-ins plus your own raceable tracks, and with a
            // small pool a series repeats a track rather than being short. Saying
            // so is better than a player wondering why the same track came up
            // twice.
            if game.tournamentPool.count < CouchGame.tournamentRaces {
                Text(
                    "Only \(game.tournamentPool.count) tracks to draw from, so some repeat.",
                    bundle: .module
                )
                .font(Retro.caption)
                .foregroundStyle(Retro.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Retro.panel.opacity(0.55))
        .overlay(RetroBevel(inset: true, thickness: 2))
        .padding(.horizontal, 16)
        .sheet(
            isPresented: Binding(
                get: { choosingFor != nil },
                set: { if !$0 { choosingFor = nil } })
        ) {
            // The same browser the single-race picker uses, told where to put the
            // answer — one surface for choosing a track, however it is being used.
            TrackBrowserView(
                game: game,
                dismiss: { choosingFor = nil },
                choose: { picked in
                    if let race = choosingFor {
                        game.setTournamentTrack(picked, atRace: race)
                    }
                },
                selectedID: choosingFor.flatMap {
                    game.pendingTournamentTracks.indices.contains($0)
                        ? game.pendingTournamentTracks[$0] : nil
                })
        }
    }

    private func row(index: Int, id: String) -> some View {
        Button {
            choosingFor = index
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: "\(index + 1).")
                    .font(Retro.font(13))
                    .foregroundStyle(Retro.inkSoft)
                if let layout = TrackThumbnail.layout(forTrackID: id, library: game.library) {
                    TrackThumbnail(layout: layout)
                        .frame(width: 48, height: 34)
                } else {
                    Rectangle()
                        .fill(Retro.panel.opacity(0.4))
                        .frame(width: 48, height: 34)
                }
                Text(verbatim: game.trackName(forID: id))
                    .font(Retro.font(13))
                    .foregroundStyle(Retro.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(Retro.caption)
                    .foregroundStyle(Retro.inkSoft)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
