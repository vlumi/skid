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
    @State private var showingSettings = LaunchFlag.consume("-skid-settings")
    @State private var showingAbout = LaunchFlag.consume("-skid-about")

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
                close: { showingSettings = false })
        }
        .sheet(isPresented: $showingAbout) {
            AboutView(close: { showingAbout = false })
        }
    }

    private var home: some View {
        VStack(spacing: 20) {
            // Settings and About ride in the corner rather than as rows: the front door
            // is about who is playing and what to do, and two more full-width buttons
            // would bury that under housekeeping.
            HStack(spacing: 10) {
                Spacer()
                RetroCornerButton(
                    symbol: "gearshape.fill", label: Text("Settings", bundle: .module)
                ) {
                    showingSettings = true
                }
                RetroCornerButton(
                    symbol: "info.circle.fill", label: Text("About", bundle: .module)
                ) {
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
        }
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    /// **Three doors, one rhythm.** START races on this device and stands
    /// alone as the primary. The nearby pair lives under its own caption, so
    /// "one device" and "several devices" read as different kinds of thing
    /// rather than three unrelated buttons. Tracks is a full-width row like
    /// the rest — it stopped being a small centred afterthought.
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

            // The same section-caption style the library uses, so grouping
            // looks the same everywhere it happens.
            Text("NEARBY DEVICES", bundle: .module)
                .font(Retro.caption)
                .foregroundStyle(Retro.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            HStack(spacing: 10) {
                Button {
                    net.host(seats: game.playerCount)
                    game.openNetworking()
                } label: {
                    Text("Host", bundle: .module).pillStyle(wide: true)
                }
                Button {
                    net.join(seats: game.playerCount)
                    game.openNetworking()
                } label: {
                    Text("Join", bundle: .module).pillStyle(wide: true)
                }
            }

            // **"Tracks", not "Track editor".** The destination is the library —
            // your tracks, where you share, rename, delete or start a new one —
            // and editing is a step deeper from there. Naming the door after the
            // room behind it sent players expecting a list into a canvas.
            Button {
                game.openTrackLibrary()
            } label: {
                Text("Tracks", bundle: .module).pillStyle(wide: true)
            }
            .padding(.top, 8)
        }
    }
}
