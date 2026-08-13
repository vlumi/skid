import SkidCore
import SwiftUI

/// Pre-race lobby: mode, player count, seating, per-player colors, AI
/// opponents, contact vs ghost, hiscores, start. Deliberately minimal —
/// only what a couch session needs.
struct SetupView: View {
    @ObservedObject var game: CouchGame
    /// Whether the track browser is showing.
    ///
    /// Opens immediately under `-skid-tracks`, which exists for the same reason
    /// `-skid-setup` does: the browser is two taps in, and `simctl` cannot tap, so a
    /// screenshot of it is otherwise unreachable.
    @State private var browsingTracks = ProcessInfo.processInfo.arguments
        .contains("-skid-tracks")

    var body: some View {
        ZStack {
            Color(red: 0.28, green: 0.55, blue: 0.23).ignoresSafeArea()
            // Scrollable, because the lobby has outgrown the smallest screens
            // (an SE can't show mode + track + race options + colors + both
            // buttons at once). `minHeight` at the viewport height keeps the
            // content CENTERED wherever it does fit, so roomy screens look
            // exactly as before and only a cramped one scrolls. A proper
            // redesign comes when the game is closer to feature-complete.
            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    lobby
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height)
                }
            }
        }
        .sheet(isPresented: $browsingTracks) {
            TrackBrowserView(game: game) { browsingTracks = false }
        }
    }

    /// The current track: its preview, its name, and the way to change it.
    private var trackRow: some View {
        Button {
            browsingTracks = true
        } label: {
            HStack(spacing: 12) {
                if let layout = TrackThumbnail.layout(
                    forTrackID: game.trackID, library: game.library)
                {
                    TrackThumbnail(layout: layout)
                        .frame(width: 84, height: 60)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.25))
                        .frame(width: 84, height: 60)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: trackDisplayName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Change track", bundle: .module)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(10)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
    }

    /// The chosen track's name, from wherever it lives.
    private var trackDisplayName: String {
        if let entry = game.library.entry(id: game.trackID) { return entry.name }
        return TrackLibrary.displayName(id: game.trackID)
    }

    private var lobby: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Race", bundle: .module)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .shadow(radius: 3)
                hiscoreLine
            }

            HStack(spacing: 10) {
                choice(Text("Race", bundle: .module), selected: game.mode == .race) {
                    game.mode = .race
                }
                choice(
                    Text("Time trial", bundle: .module), selected: game.mode == .timeTrial
                ) {
                    game.mode = .timeTrial
                }
            }

            // **The chosen track, as a picture.** A row of name chips worked for four
            // built-ins and stopped working the moment a player had tracks of their own —
            // "My track 3" says nothing about what it is. Tapping opens the browser.
            trackRow

            if game.mode == .race {
                raceOptions
            }

            colorRow

            Button {
                game.startRace()
            } label: {
                Text("Start", bundle: .module)
                    .font(.title.bold())
                    .padding(.horizontal, 48)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.92), in: Capsule())
                    .foregroundStyle(.black)
            }

            // Nearby and the editor are destinations of their own now, reached from
            // the front door rather than from the bottom of a race-setup screen.
            Button {
                game.backToMenu()
            } label: {
                Text("Back", bundle: .module).pillStyle()
            }
        }
        // Room to breathe at both ends when the content does scroll, so the
        // title and the editor button don't sit flush against the edges.
        .padding(.vertical, 20)
    }

    @ViewBuilder private var hiscoreLine: some View {
        let best = game.hiscores.best(for: game.trackID)
        HStack(spacing: 14) {
            if let lap = best.bestLapTicks {
                Text("Best lap \(formatTicks(lap))", bundle: .module)
            }
            if let race = best.raceTicks {
                Text("Best race \(formatTicks(race))", bundle: .module)
            }
        }
        .font(.footnote.monospacedDigit().bold())
        .foregroundStyle(.white.opacity(0.85))
    }

    /// **Race options — what you are racing, not who.** Who is playing is chosen on the
    /// front screen (`PlayerListView`), which is why the player count, the AI count and
    /// the seating-layout pickers are all gone from here.
    @ViewBuilder private var raceOptions: some View {
        VStack(spacing: 14) {
            // **AI is a property of the race, not of the player list.** Fill the empty
            // grid or race whoever is here alone — a count was a question nobody could
            // answer before driving.
            HStack(spacing: 10) {
                choice(Text("With AI", bundle: .module), selected: game.fillWithAI) {
                    game.fillWithAI = true
                }
                choice(Text("People only", bundle: .module), selected: !game.fillWithAI) {
                    game.fillWithAI = false
                }
            }
            if game.aiCount > 0 {
                labeledRow(Text("AI skill", bundle: .module)) {
                    ForEach(AIDriver.Difficulty.allCases, id: \.self) { level in
                        choice(
                            Text(verbatim: String(describing: level).capitalized),
                            selected: game.aiDifficulty == level
                        ) {
                            game.aiDifficulty = level
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                choice(Text("Contact", bundle: .module), selected: game.carContact) {
                    game.carContact = true
                }
                choice(Text("Ghost", bundle: .module), selected: !game.carContact) {
                    game.carContact = false
                }
            }
        }
    }

    @ViewBuilder private var colorRow: some View {
        HStack(alignment: .top, spacing: 18) {
            let humans = game.mode == .timeTrial ? 1 : game.playerCount
            ForEach(0..<humans, id: \.self) { slot in
                VStack(spacing: 6) {
                    Button {
                        game.cycleColor(slot: slot)
                    } label: {
                        Circle()
                            .fill(CouchGame.palette[game.colorIndices[slot]])
                            .frame(width: 46, height: 46)
                            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                    }
                    // **Read-only here.** Who is in a seat is chosen on the front screen
                    // now; showing a second way in would be two controls for one
                    // decision, and the underline promised an edit this screen no
                    // longer owns.
                    Text(verbatim: game.displayName(forSeat: slot))
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 64)
                    // Each player picks their own scheme — one couch can mix
                    // aim and d-pad drivers.
                    Button {
                        game.toggleScheme(slot: slot)
                    } label: {
                        Text(
                            game.schemes[slot] == .casual ? "Casual" : "Pro", bundle: .module
                        )
                        .font(.caption2.bold())
                        .frame(width: 64)  // fixed, so toggling doesn't shift the column
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.25), in: Capsule())
                        .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    /// A labeled row of choices that **wraps** rather than running off the screen.
    ///
    /// The AI row reaches nine buttons now that a solo player can face a full field,
    /// which does not fit an SE's width — reported from device, with 0 clipped off the
    /// left and 7–8 unreachable past the right edge. Same `LazyVGrid` the track picker
    /// already uses for the same reason; fixed-width columns so the numbers line up in
    /// a block instead of staggering.
    private func labeledRow(_ label: Text, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 8) {
            label
                .font(.footnote.bold())
                .foregroundStyle(.white.opacity(0.85))
            // 88, not 58: the 58 was sized for the single-digit player/AI steppers, and
            // once those went the only callers were WORD labels — which wrapped
            // mid-word into "Me/diu/m". A pill should never break a word.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10,
                content: content)
        }
    }

    /// A pill that is either chosen or not — the screen's one selection primitive.
    ///
    /// It used to take a `badge` for the signed-track seal; that moved to the browser's
    /// tiles along with the track list itself, which is the only place a seal ever
    /// appeared.
    private func choice(
        _ label: Text, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label
                .font(.callout.bold())
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    selected ? Color.white.opacity(0.9) : .black.opacity(0.25), in: Capsule()
                )
                .foregroundStyle(selected ? .black : .white)
        }
    }

}
