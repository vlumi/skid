import SkidCore
import SwiftUI

/// **The live readout while the AI laps the track you are building.**
///
/// A test drive has no finish line — it runs until the author has seen enough —
/// so there is no results card to wait for and the numbers have to be on screen
/// as they happen. The first flying lap is the answer; every lap after it is a
/// chance at a better one.
///
/// Deliberately small and cornered: the point of the screen is the car and the
/// line it takes, and a panel over the middle of the road would hide the thing
/// being judged.
struct TestDriveOverlay: View {
    @ObservedObject var game: CouchGame
    let race: Race

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                readout
                Spacer(minLength: 8)
                Button {
                    game.endTestDrive()
                } label: {
                    Text("Done", bundle: .module)
                        .font(Retro.font(13))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(Retro.panel)
                        .overlay(RetroBevel(thickness: 2))
                        .foregroundStyle(Retro.ink)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var readout: some View {
        // Lap and last are the two an author reads while watching: "is it
        // getting quicker" needs the previous lap, not just the record.
        let progress = race.cars.first?.progress
        let laps = progress?.lapTimes ?? []
        return VStack(alignment: .leading, spacing: 3) {
            line(Text("Lap", bundle: .module), "\(laps.count + 1)")
            if let best = laps.min() {
                line(Text("Best", bundle: .module), formatTicks(best))
            }
            if let last = laps.last, laps.count > 1 {
                line(Text("Last", bundle: .module), formatTicks(last))
            }
            line(Text("Top speed", bundle: .module), "\(Int(game.testDrivePeakSpeed))")
            if laps.isEmpty {
                // The first lap is from a standing start, so its time is not a
                // lap time — say so rather than letting it read as one.
                Text("First lap from a standstill", bundle: .module)
                    .font(.system(size: 9))
                    .foregroundStyle(Retro.inkSoft)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
    }

    private func line(_ label: Text, _ value: String) -> some View {
        HStack(spacing: 6) {
            label
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 6)
            Text(verbatim: value)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(minWidth: 96)
    }
}
