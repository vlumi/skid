import SkidCore
import SwiftUI

/// **The front door: who is playing, and then what to do with them.**
///
/// That order is the design, and it took a few tries to find. The screen briefly asked
/// *where* first — Solo / Couch / Nearby — but who is holding the phone is what you
/// actually know when you pick it up, and it is what makes "nearby" interesting or not.
/// Asking where first also meant a door that set a player count the list on the next
/// screen could immediately contradict.
///
/// So: the list, then three actions. The actions differ in one respect only — whose
/// device the other cars are on:
///
/// - **Start** — race here, now, with AI filling the empty grid unless told otherwise.
/// - **Host** — other devices join this field.
/// - **Join** — somebody else's field, so only the people at this device travel.
///
/// AI is a race setting rather than a list row, so nearby needs no caveat about it: the
/// protocol has no AI seat, and `aiCount` reports zero for a networked race.
struct HomeView: View {
    @ObservedObject var game: CouchGame
    let net: NetworkedGame

    // `simctl` cannot tap, so these screens are otherwise unreachable for a screenshot.
    @State private var showingSettings =
        ProcessInfo.processInfo.arguments.contains("-skid-settings")
    @State private var showingAbout =
        ProcessInfo.processInfo.arguments.contains("-skid-about")

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            // **Top-aligned inside the safe area**, not centered: the content is a
            // fixed stack, so centering it left a gap above the title on a tall phone
            // and floated the corner buttons away from the corner they name.
            ScrollView(.vertical, showsIndicators: false) {
                home
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                game: game, settings: game.settings,
                close: { showingSettings = false },
                showAbout: {
                    showingSettings = false
                    showingAbout = true
                })
        }
        .sheet(isPresented: $showingAbout) {
            AboutView(close: { showingAbout = false })
        }
    }

    /// A small icon button for the corner strip. Labelled for VoiceOver, since an icon
    /// alone says nothing to it.
    private func cornerButton(
        _ symbol: String, _ label: Text, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Retro.ink)
                .frame(width: 44, height: 44)
                .background(Retro.panel)
                .overlay(RetroBevel(thickness: 2))
        }
        .accessibilityLabel(label)
    }

    private var home: some View {
        VStack(spacing: 20) {
            // Settings and About ride in the corner rather than as rows: the front door
            // is about who is playing and what to do, and two more full-width buttons
            // would bury that under housekeeping.
            HStack(spacing: 10) {
                Spacer()
                cornerButton("gearshape.fill", Text("Settings", bundle: .module)) {
                    showingSettings = true
                }
                cornerButton("info.circle.fill", Text("About", bundle: .module)) {
                    showingAbout = true
                }
            }
            .padding(.horizontal, 16)

            // **No bevel of any kind.** A raised one read as a button and an inset one as
            // a pressed button — the frame was the problem, not its direction. Checkered
            // bands say "racing" instead, and a title nobody can mistake for a control.
            VStack(spacing: 10) {
                RetroCheckers()
                Text(verbatim: "SKID JAM")
                    .font(Retro.font(38, weight: .black))
                    .foregroundStyle(Retro.amber)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                RetroCheckers()
            }
            .padding(.vertical, 4)

            PlayerListView(game: game)
                .padding(.horizontal, 16)

            actions
                .padding(.horizontal, 16)

            Button {
                game.openEditor()
            } label: {
                Text("Track editor", bundle: .module).pillStyle()
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                game.openSetup()
            } label: {
                Text("START", bundle: .module)
                    .font(Retro.font(20, weight: .black))
                    .foregroundStyle(Retro.onHighlight)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Retro.highlight)
                    .overlay(RetroBevel())
            }

            HStack(spacing: 10) {
                Button {
                    net.host(seats: game.playerCount)
                    game.openNetworking()
                } label: {
                    Text("Host nearby", bundle: .module).pillStyle()
                }
                Button {
                    net.join(seats: game.playerCount)
                    game.openNetworking()
                } label: {
                    Text("Join nearby", bundle: .module).pillStyle()
                }
            }

        }
    }
}
