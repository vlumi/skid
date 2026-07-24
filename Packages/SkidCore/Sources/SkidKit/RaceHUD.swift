import SkidCore
import SwiftUI

/// Zone-aware HUD: each player's chip sits in their own zone's home corner,
/// rotated to face them; the countdown mirrors for flipped players. Solo
/// keeps the classic top-left block (with AI opponents listed).
struct RaceHUD: View {
    let race: Race
    let colors: [Color]
    @ObservedObject var rig: CouchRig
    let size: CGSize

    /// Debounced finishing position per car index (P1 = 1). Recomputed from
    /// `race.standings` each tick, but a change is only shown after it has
    /// held for `placeDebounceTicks` — so two near-level cars trading the lead
    /// frame-to-frame don't flicker the number. Time trial leaves this empty.
    @State private var shownPlace: [Int: Int] = [:]
    /// A pending place change and the tick it first appeared, per car.
    @State private var pendingPlace: [Int: (place: Int, since: Tick)] = [:]
    private static let placeDebounceTicks: Tick = 24  // ~0.4s at 60 Hz

    private var hasFlippedZone: Bool {
        rig.players.contains { $0.up.y > 0 }
    }

    var body: some View {
        ZStack {
            countdown
            // Every layout — including 1P — shows one chip per player in
            // their own control band (1P is the face-to-face layout with a
            // single near player).
            ForEach(Array(rig.players.enumerated()), id: \.offset) { index, controls in
                playerChip(index: index, controls: controls)
            }
        }
        .allowsHitTesting(false)
        .onAppear { updatePlaces() }
        .onChangeCompat(of: race.tick) { _ in updatePlaces() }
    }

    /// Fold `race.standings` into a debounced per-car place. A car's shown
    /// place only moves once its new place has been stable for the debounce
    /// window; the first reading (and finished cars, which don't waver) apply
    /// at once. Only meaningful for lap races.
    private func updatePlaces() {
        guard race.config.laps != nil else {
            if !shownPlace.isEmpty { shownPlace = [:] }
            return
        }
        let ranking = race.standings
        for (place, carIndex) in ranking.enumerated() {
            let newPlace = place + 1
            let finished = race.cars[carIndex].progress.finishedAt != nil
            if shownPlace[carIndex] == nil || finished {
                shownPlace[carIndex] = newPlace  // first reading / settled result
                pendingPlace[carIndex] = nil
            } else if newPlace == shownPlace[carIndex] {
                pendingPlace[carIndex] = nil  // back to what's shown; cancel
            } else if let pending = pendingPlace[carIndex], pending.place == newPlace {
                if race.tick - pending.since >= Self.placeDebounceTicks {
                    shownPlace[carIndex] = newPlace  // held long enough; promote
                    pendingPlace[carIndex] = nil
                }
            } else {
                pendingPlace[carIndex] = (newPlace, race.tick)  // start the timer
            }
        }
    }

    @ViewBuilder private var countdown: some View {
        let label: Text? = {
            if case .countdown(let remaining) = race.phase {
                return Text(verbatim: "\((remaining + Race.tickRate - 1) / Race.tickRate)")
            }
            if race.phase == .running, race.raceTicks < Race.tickRate * 3 / 4 {
                return Text("GO!", bundle: .module)
            }
            return nil
        }()
        if let label {
            if hasFlippedZone {
                // One for each side of the table.
                bigLabel(label)
                    .position(x: size.width / 2, y: size.height * 0.7)
                bigLabel(label)
                    .rotationEffect(.degrees(180))
                    .position(x: size.width / 2, y: size.height * 0.3)
            } else {
                bigLabel(label)
                    .position(x: size.width / 2, y: size.height / 2)
            }
        }
    }

    private func bigLabel(_ text: Text) -> some View {
        text
            .font(.system(size: 84, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(radius: 4)
    }

    /// One chip per player, along the MAP-SIDE (inner) edge
    /// of their control band — the clear spot: away from the screen-top notch
    /// and safe-area, and away from where the thumb rests the stick (mid/outer
    /// band). Reads as "just outside the track", rotated to face the player.
    @ViewBuilder private func playerChip(index: Int, controls: PlayerControls) -> some View {
        if race.cars.indices.contains(index) {
            let car = race.cars[index]
            let flipped = controls.up.y > 0
            // Placed within the CONTENT rect (inside the safe area), never the
            // full box — so the chip clears the notch / home indicator.
            let zone = controls.content
            // Map-side edge: the band's bottom for a flipped (top) band, its
            // top for a near (bottom) band — both the edge nearest the map.
            let x = zone.midX
            let y = flipped ? zone.maxY - 18 : zone.minY + 18
            let content = VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(index < colors.count ? colors[index] : .white)
                        .frame(width: 11, height: 11)
                    if let laps = race.config.laps {
                        chipLine(car: car, index: index, laps: laps)
                    } else {
                        // Time trial: current lap clock + best (was the solo block).
                        HStack(spacing: 6) { timeTrialLines(car: car) }
                    }
                }
                // On finish, the player's splits, so it's unmistakable they're
                // done — and how each lap went.
                if car.progress.finishedAt != nil, !car.progress.lapTimes.isEmpty {
                    finishSplits(car: car)
                }
            }
            content
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .rotationEffect(flipped ? .degrees(180) : .zero)
                .position(x: x, y: y)
        }
    }

    @ViewBuilder private func chipLine(car: Car, index: Int, laps: Int) -> some View {
        HStack(spacing: 5) {
            if let place = shownPlace[index] {
                Text(verbatim: "P\(place)")
                    .font(.subheadline.monospacedDigit().bold())
            }
            if let finished = car.progress.finishedAt {
                Text(verbatim: formatTicks(finished - race.config.countdownTicks))
                    .font(.subheadline.monospacedDigit().bold())
            } else {
                Text("Lap \(min(car.progress.lap + 1, laps))/\(laps)", bundle: .module)
                    .font(.subheadline.monospacedDigit())
            }
        }
    }

    /// The player's lap splits, shown in the band once they've finished — the
    /// clear "you're done, here's how it went" state.
    @ViewBuilder private func finishSplits(car: Car) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(car.progress.lapTimes.enumerated()), id: \.offset) { lap, ticks in
                Text(verbatim: formatTicks(ticks))
                    .font(.caption2.monospacedDigit())
                    .opacity(ticks == car.progress.bestLapTicks ? 1 : 0.7)
                if lap < car.progress.lapTimes.count - 1 {
                    Text(verbatim: "·").font(.caption2).opacity(0.4)
                }
            }
        }
    }

    @ViewBuilder private func timeTrialLines(car: Car) -> some View {
        let lapTicks = max(
            0, race.tick - max(car.progress.lapStartTick, race.config.countdownTicks))
        Text(verbatim: formatTicks(lapTicks))
            .font(.title3.monospacedDigit().bold())
        if let best = car.progress.bestLapTicks {
            Text("Best \(formatTicks(best))", bundle: .module)
                .font(.subheadline.monospacedDigit())
        }
    }
}

/// Final standings once every car has taken the flag.
struct ResultsCard: View {
    let game: CouchGame
    let race: Race
    let colors: [Color]

    var body: some View {
        let standings = race.cars.enumerated().sorted { a, b in
            (a.element.progress.finishedAt ?? .max) < (b.element.progress.finishedAt ?? .max)
        }
        VStack(spacing: 14) {
            ForEach(Array(standings.enumerated()), id: \.offset) { place, entry in
                let (carIndex, car) = entry
                HStack(spacing: 10) {
                    Text(verbatim: "\(place + 1).")
                        .font(.title3.monospacedDigit().bold())
                    Circle()
                        .fill(carIndex < colors.count ? colors[carIndex] : .white)
                        .frame(width: 16, height: 16)
                    if let finished = car.progress.finishedAt {
                        Text(verbatim: formatTicks(finished - race.config.countdownTicks))
                            .font(.title3.monospacedDigit())
                    }
                    if let best = car.progress.bestLapTicks {
                        Text("Best \(formatTicks(best))", bundle: .module)
                            .font(.footnote.monospacedDigit())
                            .opacity(0.75)
                    }
                }
            }
            HStack(spacing: 12) {
                Button {
                    game.raceAgain()
                } label: {
                    Text("Race again", bundle: .module).pillStyle()
                }
                Button {
                    game.backToSetup()
                } label: {
                    Text("Setup", bundle: .module).pillStyle()
                }
            }
        }
        .padding(24)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }
}
