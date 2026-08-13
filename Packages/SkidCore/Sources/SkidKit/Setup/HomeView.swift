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
/// - **Start** — race here, now. AI rows are cars in it.
/// - **Host** — other devices join this field. The host's sim owns it, so AI rows still
///   mean something.
/// - **Join** — somebody else's field, so only the people at this device travel. AI rows
///   stay behind, and the button says so rather than dropping them silently.
struct HomeView: View {
    @ObservedObject var game: CouchGame
    let net: NetworkedGame

    var body: some View {
        ZStack {
            Color(red: 0.28, green: 0.55, blue: 0.23).ignoresSafeArea()
            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    home
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height)
                }
            }
        }
    }

    private var home: some View {
        VStack(spacing: 20) {
            Text(verbatim: "SKID JAM")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .shadow(radius: 3)

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
        .padding(.vertical, 18)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                game.openSetup()
            } label: {
                Text("Start", bundle: .module)
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.92), in: Capsule())
                    .foregroundStyle(.black)
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

            // Said here rather than enforced by reshaping the list: a nearby field is
            // built by whoever hosts it, and the protocol has no AI seat at all.
            if game.aiCount > 0 {
                Text("Joining a race leaves the AI cars behind.", bundle: .module)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }
}
