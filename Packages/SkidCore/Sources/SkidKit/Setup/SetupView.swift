import SkidCore
import SwiftUI

/// Pre-race lobby: mode, player count, seating, per-player colors, AI
/// opponents, contact vs ghost, hiscores, start. Deliberately minimal —
/// only what a couch session needs.
struct SetupView: View {
    @ObservedObject var game: CouchGame
    /// Which seat's profile picker is open, if any.
    @State private var namingSeat: Int?

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
        // `Int` is not `Identifiable`, so this is the boolean form with the seat read
        // alongside — rather than a wrapper type that exists only to satisfy a sheet.
        .sheet(
            isPresented: Binding(
                get: { namingSeat != nil },
                set: { if !$0 { namingSeat = nil } }
            )
        ) {
            SeatProfileSheet(game: game, seat: namingSeat ?? 0) { namingSeat = nil }
        }
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

            // Wraps, because the built-ins outgrew one row on a small phone
            // (four tracks plus the custom slot). Fixed-width columns so the
            // chips line up rather than staggering by name length.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10
            ) {
                ForEach(TrackLibrary.all, id: \.id) { track in
                    choice(trackName(track.id), selected: game.trackID == track.id) {
                        game.trackID = track.id
                    }
                }
                // The custom slot: one permanent place for your own design,
                // raced with the full setup (players, AI, laps) like any
                // built-in. Only selectable once it compiles to a real track.
                customTrackChoices
            }

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

    /// Display name for a built-in track id.
    /// A built-in's display name, from the library rather than a switch here.
    ///
    /// This used to hardcode the names of the four hand-authored circuits, so once
    /// they were replaced by piece-built tracks every one of them fell through to
    /// the default and the picker showed "Practice" three times over. Names belong
    /// with the tracks. (The custom slot is drawn by `customTrackChoice`, not
    /// through here.)
    private func trackName(_ id: String) -> Text {
        Text(verbatim: TrackLibrary.displayName(id: id))
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
                    // **The seat's name, and the way into a profile.** A guest reads
                    // "P1" — not a placeholder, just what a guest is called — and
                    // tapping it is how somebody claims the seat. Put on the label
                    // rather than behind a separate button because the label is
                    // already the thing that says who this is.
                    Button {
                        namingSeat = slot
                    } label: {
                        Text(verbatim: game.displayName(forSeat: slot))
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 64)
                            .underline(game.profile(inSeat: slot) == nil)
                    }
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
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10,
                content: content)
        }
    }

    /// Your own tracks, newest first.
    ///
    /// Only the raceable ones appear — an unfinished ring in the editor is not
    /// a choice, and greying out every draft would be noise. Raceability is read
    /// from the entry, never recompiled: this used to ask `customTrack() != nil`
    /// per render, which compiled the layout every frame.
    @ViewBuilder private var customTrackChoices: some View {
        ForEach(game.library.raceable) { entry in
            choice(
                Text(entry.name), selected: game.trackID == entry.trackID,
                badge: entry.signatureIsValid ? "seal" : nil
            ) {
                game.trackID = entry.trackID
            }
        }
    }

    /// `badge` marks a track that arrived signed — the verdict is read from the
    /// entry, computed once at import.
    private func choice(
        _ label: Text, selected: Bool, badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                label
                if let badge { Image(systemName: badge).font(.caption2) }
            }
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
