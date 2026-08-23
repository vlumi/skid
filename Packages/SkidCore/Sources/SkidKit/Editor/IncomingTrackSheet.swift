import SkidCore
import SwiftUI

/// **"Somebody sent you a track. Want it?"**
///
/// Shown when a link is tapped or a code is scanned. An offer rather than a
/// silent import: the app is being handed something by a third party, and one
/// that writes to your library without asking is one you stop trusting.
///
/// The preview is the point — a name is a claim, while the picture is the track.
struct IncomingTrackSheet: View {
    @ObservedObject var game: CouchGame
    let incoming: IncomingTrack
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    RetroTitle(Text("A track for you", bundle: .module))
                    previewPanel
                    buttons
                }
                .padding(16)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var previewPanel: some View {
        VStack(spacing: 10) {
            TrackThumbnail(layout: incoming.layout)
                .frame(height: 160)
            Text(verbatim: incoming.name ?? String(localized: "Unnamed track", bundle: .module))
                .font(Retro.body)
                .foregroundStyle(Retro.ink)
            // The stats say what a picture cannot: how long, how many corners,
            // whether it climbs — enough to know if it is worth keeping.
            statsLine
            if incoming.alreadyHave {
                Text("You already have this track.", bundle: .module)
                    .font(Retro.caption)
                    .foregroundStyle(Retro.inkSoft)
            }
        }
        .retroPanel()
    }

    @ViewBuilder private var statsLine: some View {
        let stats = TrackStats.of(walk: incoming.layout.walk())
        Text(
            verbatim: [
                WorldScale.distanceLabel(units: stats.length, in: game.settings.units),
                "\(stats.corners) corners",
            ].joined(separator: " · ")
        )
        .font(Retro.caption)
        .foregroundStyle(Retro.inkSoft)
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            // **Nothing to add when you already have it.** Identity is the
            // content, so a second copy of the same road is not a thing the
            // library can hold — offering "add anyway" would be a button that
            // silently does nothing.
            if incoming.alreadyHave {
                Button {
                    game.declineIncomingTrack()
                    dismiss()
                } label: {
                    Text("OK", bundle: .module)
                        .retroButton(wide: true, tint: Retro.highlight)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    _ = game.acceptIncomingTrack()
                    dismiss()
                } label: {
                    Text("Add to my tracks", bundle: .module)
                        .retroButton(wide: true, tint: Retro.highlight)
                }
                .buttonStyle(.plain)
                Button {
                    game.declineIncomingTrack()
                    dismiss()
                } label: {
                    Text("No thanks", bundle: .module).retroButton(wide: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
