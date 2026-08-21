import SkidCore
import SwiftUI

/// **The series standings, shown after every race of a tournament.**
///
/// Its own file rather than more of `ResultsCard`: that card answers "how did
/// this race go", this answers "how is the series going", and `RaceHUD.swift`
/// is at its length limit anyway.
struct TournamentStandings: View {
    @ObservedObject var game: CouchGame
    let series: Tournament
    let colors: [Color]

    var body: some View {
        VStack(spacing: 8) {
            header
            let points = series.pointsBySeat
            let winners = Set(series.winners)
            ForEach(Array(series.standings.enumerated()), id: \.offset) { place, seat in
                row(place: place, seat: seat, points: points, winners: winners)
            }
            if series.isComplete { winnerLine }
        }
        .padding(.top, 4)
    }

    private var header: some View {
        // Mid-series this counts races; complete, it says so — "Race 4 of 4"
        // on the final screen would leave a player waiting for a fifth.
        Group {
            if series.isComplete {
                Text("Tournament over", bundle: .module)
            } else {
                Text(
                    "Race \(series.completedCount) of \(series.raceCount)",
                    bundle: .module)
            }
        }
        .font(Retro.heading)
        .foregroundStyle(Retro.inkSoft)
    }

    private func row(place: Int, seat: Int, points: [Int], winners: Set<Int>) -> some View {
        // A shared win means no single leader, so the marker goes on EVERY
        // winning row rather than on the first — the caret would otherwise claim
        // a winner the rules deliberately refuse to pick.
        let won = winners.contains(seat)
        return HStack(spacing: 8) {
            Text(verbatim: won ? "▸" : " ")
                .font(Retro.body)
                .foregroundStyle(Retro.amber)
            Circle()
                .fill(seat < colors.count ? colors[seat] : .white)
                .frame(width: 14, height: 14)
            Text(verbatim: game.displayName(forSeat: seat))
                .font(Retro.font(14))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text(verbatim: "\(points[seat])")
                .font(Retro.font(16))
        }
        .foregroundStyle(won ? Retro.highlight : Retro.ink)
    }

    /// Named plainly, and in the plural when the series ended level — the
    /// decided rule is that everyone on the top score won, so the screen has to
    /// be able to say two names without implying one of them came second.
    private var winnerLine: some View {
        let names = series.winners.map { game.displayName(forSeat: $0) }
        return Group {
            if names.count == 1 {
                Text("\(names[0]) wins", bundle: .module)
            } else {
                Text("Tied: \(names.joined(separator: ", "))", bundle: .module)
            }
        }
        .font(Retro.font(15))
        .foregroundStyle(Retro.highlight)
        .padding(.top, 2)
    }
}
