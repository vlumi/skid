import SkidCore
import SwiftUI

/// **The card that ends a race**: finishing order, records taken, and what to do
/// next — which in a tournament is "the next race" and a running points table.
///
/// Split out of `RaceHUD.swift` on the file-length limit when the series flow
/// landed, and a clean seam: the HUD is live chrome, this is the aftermath.
struct ResultsCard: View {
    /// Observed, not held flat: the record line reads `game.runRecords`, which is written
    /// on the frame the finish lands — the same frame this card first appears.
    @ObservedObject var game: CouchGame
    /// A networked race exits to the LOBBY rather than to setup — the connection is
    /// worth keeping, since the next race reuses it.
    let session: GameSession
    let net: NetworkedGame
    let race: Race
    let colors: [Color]

    var body: some View {
        // Rank by the same deterministic standings the in-race chip uses, and
        // find the race's overall fastest lap so it can be called out.
        let order = race.standings
        let fastestLap = race.cars.compactMap(\.progress.bestLapTicks).min()
        VStack(spacing: 14) {
            ForEach(Array(order.enumerated()), id: \.offset) { place, carIndex in
                let car = race.cars[carIndex]
                let ownsFastest =
                    car.progress.bestLapTicks != nil
                    && car.progress.bestLapTicks == fastestLap
                HStack(spacing: 10) {
                    Text(verbatim: "\(place + 1).")
                        .font(Retro.font(19))
                    Circle()
                        .fill(carIndex < colors.count ? colors[carIndex] : .white)
                        .frame(width: 16, height: 16)
                    if let finished = car.progress.finishedAt {
                        Text(verbatim: formatTicks(finished - race.config.countdownTicks))
                            .font(Retro.font(19, weight: .regular))
                    }
                    if let best = car.progress.bestLapTicks {
                        // The race's overall fastest lap gets a gold star; the
                        // star sits in a fixed slot (invisible on other rows)
                        // so every "Best" lines up, and the time weight stays
                        // uniform — the star alone marks the winner.
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(Retro.caption)
                                .opacity(ownsFastest ? 1 : 0)
                            Text("Best \(formatTicks(best))", bundle: .module)
                                .font(Retro.font(13, weight: .regular))
                        }
                        .foregroundStyle(ownsFastest ? Retro.highlight : Retro.ink)
                        .opacity(ownsFastest ? 1 : 0.75)
                    }
                }
            }
            recordLines
            // A series folds this race into its standings the moment the card
            // appears, and shows where everyone stands. `record` is guarded
            // against double-counting, so a redraw cannot score a race twice.
            if game.isTestDriving {
                TestDriveReport(game: game, race: race)
                HStack(spacing: 12) {
                    Button {
                        game.testDriveAgain()
                    } label: {
                        Text("Drive again", bundle: .module).pillStyle()
                    }
                    Button {
                        game.endTestDrive()
                    } label: {
                        Text("Back to editor", bundle: .module).pillStyle()
                    }
                }
            } else if game.mode == .tournament, let series = game.tournament {
                TournamentStandings(game: game, series: series, colors: colors)
                tournamentButtons(series: series)
            } else {
                singleRaceButtons
            }
        }
        .padding(24)
        .background(Retro.panel)
        .overlay(RetroBevel())
        .foregroundStyle(Retro.ink)
        // **Scored on appear, not while rendering.** Folding the result in from a
        // computed property would mutate the game as a side effect of layout,
        // which SwiftUI may run more than once per frame. `record` also refuses a
        // second entry once the series is complete, so the two guards are
        // independent.
        .onAppear { game.recordTournamentResult(race) }
    }

    @ViewBuilder private func tournamentButtons(series: Tournament) -> some View {
        HStack(spacing: 12) {
            if series.isComplete {
                Button {
                    game.abandonTournament()
                } label: {
                    Text("Done", bundle: .module).pillStyle()
                }
            } else {
                Button {
                    game.advanceTournament()
                } label: {
                    Text("Next race", bundle: .module).pillStyle()
                }
                Button {
                    game.abandonTournament()
                } label: {
                    Text("Quit series", bundle: .module).pillStyle()
                }
            }
        }
    }

    @ViewBuilder private var singleRaceButtons: some View {
        HStack(spacing: 12) {
            Button {
                // **A networked race exits to the LOBBY, not to setup**, and
                // "race again" is the host's call there: the connection and the
                // roster are already agreed, so the next race costs one message.
                // Keeping the session is the difference between a couch playing
                // five short races and force-quitting between each one.
                if session.isNetworked {
                    net.returnToLobby()
                    game.openNetworking()
                } else {
                    game.raceAgain()
                }
            } label: {
                Text(
                    session.isNetworked ? "Lobby" : "Race again", bundle: .module
                ).pillStyle()
            }
            Button {
                if session.isNetworked { net.leave() }
                game.backToSetup()
            } label: {
                Text("Setup", bundle: .module).pillStyle()
            }
        }
    }

    /// **What this race took off the record book**, and what it beat.
    ///
    /// The beaten time is the point: "best lap 0:04.81" is a number, while "beat 0:05.28"
    /// is an achievement. A first-ever record has nothing behind it and says so rather
    /// than inventing a comparison.
    ///
    /// Silent when nothing fell — including every run that does not qualify (more than one
    /// human, slowed pace, dialed physics), which records nothing by design.
    @ViewBuilder private var recordLines: some View {
        let records = game.runRecords
        if !records.isEmpty {
            VStack(spacing: 4) {
                if let lap = records.lapRecord {
                    recordLine(Text("Best lap", bundle: .module), lap)
                }
                if let race = records.raceRecord {
                    recordLine(Text("Best race", bundle: .module), race)
                }
            }
        }
    }

    private func recordLine(_ label: Text, _ improvement: RunRecords.Improvement) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(Retro.caption)
            label
                .font(.footnote.bold())
            Text(verbatim: formatTicks(improvement.ticks))
                .font(Retro.font(13))
            if let previous = improvement.previous {
                Text("beat \(formatTicks(previous))", bundle: .module)
                    .font(.caption2.monospacedDigit())
                    .opacity(0.7)
            } else {
                Text("first", bundle: .module)
                    .font(Retro.caption)
                    .opacity(0.7)
            }
        }
        .foregroundStyle(Retro.highlight)
    }
}
