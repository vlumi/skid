import SkidCore
import SwiftUI

/// **The front door: who are you playing with?**
///
/// The first screen of the redesign, and the question it asks is the one the old flat
/// setup screen hid behind a player-count stepper. A stepper from 1 to 4 makes
/// "playing alone" and "playing with three friends" the same act with a different
/// number — when they are the two different reasons somebody opens the app, and they
/// want different things next. Solo needs no seating layout; couch does. Nearby has
/// its own lobby and needs neither.
///
/// So the split is up front, and each destination then asks only what it needs.
///
/// Deliberately four destinations and nothing else. Everything the old screen put on
/// one surface — mode, track, seating, AI, contact, colors — belongs to whichever of
/// these actually cares about it.
struct HomeView: View {
    @ObservedObject var game: CouchGame

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
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            Text(verbatim: "SKID JAM")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .shadow(radius: 3)

            VStack(spacing: 12) {
                // Solo and Couch are the same destination with a different seat
                // count — the screen after this one is what differs, not the code
                // path. `players` is set here so that screen never has to ask.
                destination(
                    Text("Solo", bundle: .module),
                    caption: Text("One player, against the AI or the clock", bundle: .module)
                ) {
                    game.playerCount = 1
                    game.openSetup()
                }
                destination(
                    Text("Couch", bundle: .module),
                    caption: Text("Two to four sharing this screen", bundle: .module)
                ) {
                    // Two is the smallest couch, and the commonest: land there
                    // rather than on whatever the last session used, which could
                    // be one and make the choice a lie.
                    game.playerCount = max(2, game.playerCount)
                    game.openSetup()
                }
                destination(
                    Text("Nearby", bundle: .module),
                    caption: Text("Race other devices in the room", bundle: .module)
                ) {
                    game.openNetworking()
                }
            }
            .padding(.horizontal, 28)

            // The editor is a first-class destination rather than a button on the
            // race-setup sheet, which is where it used to live: building a track is
            // not a step on the way to starting a race.
            //
            // Kept close to the three doors rather than pushed to the bottom edge by a
            // second `Spacer`: on an SE that left an obvious dead band between Nearby
            // and this, which read as a missing fourth option rather than as breathing
            // room. The remaining spacer below floats the whole group toward center.
            Button {
                game.openEditor()
            } label: {
                Text("Track editor", bundle: .module).pillStyle()
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 20)
    }

    /// One top-level choice: a title and a line saying who it is for.
    ///
    /// The caption is the point of the redesign in miniature — the old screen
    /// offered controls and left the player to infer what they were for.
    private func destination(
        _ title: Text, caption: Text, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                title
                    .font(.title2.bold())
                    .foregroundStyle(.black)
                caption
                    .font(.footnote)
                    .foregroundStyle(.black.opacity(0.62))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
