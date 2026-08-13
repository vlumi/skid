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
            // The title says which door you came through, so the screen is
            // self-explanatory rather than a wall of controls with a logo on top.
            VStack(spacing: 6) {
                (game.playerCount == 1
                    ? Text("Solo", bundle: .module) : Text("Couch", bundle: .module))
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

    @ViewBuilder private var raceOptions: some View {
        VStack(spacing: 14) {
            // **Only offered for a couch session.** Solo came in through its own
            // door, so a "Players" row would immediately contradict the choice just
            // made — and one-tap-to-2 would leave a screen titled Solo seating two.
            // Changing your mind means going back, which is one tap and unambiguous.
            if game.playerCount > 1 {
                labeledRow(Text("Players", bundle: .module)) {
                    ForEach(2...CouchGame.maxLocalPlayers, id: \.self) { count in
                        squareChoice(String(count), selected: game.playerCount == count) {
                            game.playerCount = count
                        }
                    }
                }
            }
            if game.playerCount == 2 {
                HStack(spacing: 10) {
                    choice(
                        Text("Side-by-side", bundle: .module), selected: !game.faceToFace
                    ) {
                        game.faceToFace = false
                    }
                    choice(Text("Face-to-face", bundle: .module), selected: game.faceToFace) {
                        game.faceToFace = true
                    }
                }
            }
            if game.playerCount == 3 {
                openCornerPicker
            }
            // AI fills the rest of the FIELD, not just the four local seats — so a
            // solo player can face eight of them. Nine is the grid's own limit
            // (`CouchGame.maxCars`), which the palette matches.
            if game.playerCount < CouchGame.maxCars {
                labeledRow(Text("AI", bundle: .module)) {
                    ForEach(0...(CouchGame.maxCars - game.playerCount), id: \.self) { count in
                        squareChoice(String(count), selected: game.aiCount == count) {
                            game.aiCount = count
                        }
                    }
                }
            }
            if game.aiCount > 0 {
                HStack(spacing: 10) {
                    choice(
                        Text("Easy", bundle: .module),
                        selected: game.aiDifficulty == .easy
                    ) {
                        game.aiDifficulty = .easy
                    }
                    choice(
                        Text("Medium", bundle: .module),
                        selected: game.aiDifficulty == .medium
                    ) {
                        game.aiDifficulty = .medium
                    }
                    choice(
                        Text("Hard", bundle: .module),
                        selected: game.aiDifficulty == .hard
                    ) {
                        game.aiDifficulty = .hard
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

    /// 3P seating: a 2×2 mini-map of the screen; tap the quadrant that
    /// should stay open (marked ×), the rest get the players in order.
    @ViewBuilder private var openCornerPicker: some View {
        VStack(spacing: 6) {
            Text("Open corner", bundle: .module)
                .font(.footnote.bold())
                .foregroundStyle(.white.opacity(0.85))
            let grid: [[ZoneCorner]] = [[.topLeft, .topRight], [.bottomLeft, .bottomRight]]
            VStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(grid[row], id: \.self) { corner in
                            let isOpen = game.openCorner == corner
                            Button {
                                game.openCorner = corner
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            isOpen
                                                ? Color.black.opacity(0.4)
                                                : .white.opacity(0.85))
                                    if isOpen {
                                        Text(verbatim: "×")
                                            .font(.headline)
                                            .foregroundStyle(.white.opacity(0.8))
                                    } else if let slot = slotIndex(for: corner) {
                                        Circle()
                                            .fill(CouchGame.palette[game.colorIndices[slot]])
                                            .frame(width: 16, height: 16)
                                    }
                                }
                                .frame(width: 64, height: 40)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Which player slot a corner gets in the 3P layout (zones fill in
    /// bottom-left → bottom-right → top-left → top-right order, skipping
    /// the open corner).
    private func slotIndex(for corner: ZoneCorner) -> Int? {
        ZoneCorner.allCases.filter { $0 != game.openCorner }.firstIndex(of: corner)
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

    private func squareChoice(
        _ label: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(.title3.bold())
                .frame(width: 48, height: 40)
                .background(
                    selected ? Color.white.opacity(0.9) : .black.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .foregroundStyle(selected ? .black : .white)
        }
    }
}
