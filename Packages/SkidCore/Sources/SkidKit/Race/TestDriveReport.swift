import SkidCore
import SwiftUI

/// **What the AI's laps say about the track you are building.**
///
/// The numbers an author actually wants after watching a drive, which are the
/// ones that only exist once something has driven it: what a lap costs, and
/// whether the track has anywhere that reaches speed.
///
/// The geometry — length, corners, climb — is `TrackStats` and shown while
/// building, so it is deliberately not repeated here.
struct TestDriveReport: View {
    @ObservedObject var game: CouchGame
    let race: Race

    var body: some View {
        VStack(spacing: 6) {
            Text("Test drive", bundle: .module)
                .font(Retro.heading)
                .foregroundStyle(Retro.inkSoft)
            if let best = race.cars.compactMap(\.progress.bestLapTicks).min() {
                line(Text("Best lap", bundle: .module), formatTicks(best))
            } else {
                // A drive with no completed lap is itself the finding: the AI
                // could not get round, which is a track problem worth naming
                // rather than an empty panel.
                Text("No car completed a lap.", bundle: .module)
                    .font(Retro.caption)
                    .foregroundStyle(Retro.danger)
            }
            if let slowest = race.cars.compactMap(\.progress.bestLapTicks).max(),
                let best = race.cars.compactMap(\.progress.bestLapTicks).min(),
                slowest != best
            {
                // The spread across three drivers says how punishing the track
                // is: a wide gap means small mistakes cost a lot here.
                line(Text("Spread", bundle: .module), "+\(formatTicks(slowest - best))")
            }
            line(Text("Top speed", bundle: .module), "\(Int(game.testDrivePeakSpeed))")
        }
    }

    private func line(_ label: Text, _ value: String) -> some View {
        HStack(spacing: 8) {
            label
                .font(Retro.font(13))
                .foregroundStyle(Retro.inkSoft)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .font(Retro.font(15))
                .foregroundStyle(Retro.ink)
        }
    }
}
