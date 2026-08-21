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
    /// What this run has taken off the record book. Only a time trial reads it — a race
    /// reports its records on the results screen, which a trial never reaches.
    var records: RunRecords = .none
    /// The race has begun (ready gate cleared). Until then the countdown is
    /// suppressed — the sim sits frozen at tick 0 (phase `.countdown`), which
    /// would otherwise flash a "3" behind the Play button.
    var started: Bool = true
    /// Where the start gantry sits — computed by `StartLights.gantryCenter`, so
    /// it can dodge a grid parked at the screen center.
    var gantryCenter: CGPoint = .zero

    /// Debounced finishing position per car index (P1 = 1). Recomputed from
    /// `race.standings` each tick, but a change is only shown after it has
    /// held for `placeDebounceTicks` — so two near-level cars trading the lead
    /// frame-to-frame don't flicker the number. Time trial leaves this empty.
    @State private var shownPlace: [Int: Int] = [:]
    /// A pending place change and the tick it first appeared, per car.
    @State private var pendingPlace: [Int: (place: Int, since: Tick)] = [:]
    private static let placeDebounceTicks: Tick = 24  // ~0.4s at 60 Hz

    var body: some View {
        ZStack {
            countdown
            // Every layout — including 1P — shows one chip per player in
            // their own control band (1P is the face-to-face layout with a
            // single near player).
            ForEach(Array(rig.players.enumerated()), id: \.offset) { _, controls in
                // **Keyed by the SEAT the band drives, not by band index.** On a
                // networked guest, band 0 drives seat 1 — so indexing `race.cars` and
                // `colors` by the band showed the guest the HOST's car and color.
                // Reported from device: the chip was blue on both screens when the
                // cars were blue and green.
                playerChip(
                    index: race.cars.firstIndex { $0.id == controls.player } ?? 0,
                    controls: controls)
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

    /// **The start gantry**, over the map — at the screen center unless the grid
    /// is there, in which case it dodges (see `StartLights.gantryCenter`).
    ///
    /// One copy, not two. The numbers this replaces had to be drawn twice and mirrored,
    /// because a "3" upside down is not a 3 — and even then the players sitting sideways
    /// in a four-way game read neither copy. A row of lights is symmetric, so one is
    /// enough for every seat. See `StartLights`.
    @ViewBuilder private var countdown: some View {
        if started {
            let seconds: Int? = {
                if case .countdown(let remaining) = race.phase {
                    return (remaining + Race.tickRate - 1) / Race.tickRate
                }
                // Held briefly past the start with every lamp dark: the lights GOING OUT
                // is the signal, so they have to still be there to go out.
                if race.phase == .running, race.raceTicks < Race.tickRate * 3 / 4 {
                    return 0
                }
                return nil
            }()
            if let seconds {
                StartLights(secondsRemaining: seconds, started: seconds <= 0)
                    .position(gantryCenter)
            }
        }
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
            let finished = car.progress.finishedAt != nil && race.config.laps != nil
            let content =
                finished
                ? AnyView(finishCard(car: car, index: index))
                : AnyView(racingChip(car: car, index: index))
            // While racing the chip hugs the map-side edge (thumb rests
            // mid/outer band, so keep status near the track). On finish it
            // moves to the band's center and becomes a proper card — plenty of
            // room now that the race is over.
            //
            // Anchored by its EDGE, not its center: `.position` centers what it
            // places, so a time trial's lap list — which is as tall as it has
            // rows — grew half its height back over the track. Pinning the
            // map-side edge makes it grow inward, into the band's empty middle.
            content
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .rotationEffect(flipped ? .degrees(180) : .zero)
                .frame(width: zone.width, alignment: .center)
                .frame(
                    maxHeight: .infinity,
                    alignment: finished ? .center : (flipped ? .bottom : .top)
                )
                .padding(finished ? [] : (flipped ? .bottom : .top), 18)
                .frame(width: zone.width, height: zone.height)
                .position(x: zone.midX, y: zone.midY)
        }
    }

    /// The compact in-race chip: color dot, live position, lap counter.
    @ViewBuilder private func racingChip(car: Car, index: Int) -> some View {
        // Top-aligned, not centered: a time trial's column is many rows tall, and a
        // centered dot floats off beside the middle of the list with nothing to do
        // with it. Against the first line it reads as labelling the clock.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(index < colors.count ? colors[index] : .white)
                .frame(width: 11, height: 11)
            if let laps = race.config.laps {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        if let place = shownPlace[index] {
                            Text(verbatim: ordinal(place))
                                .font(Retro.font(15))
                        }
                        Text("Lap \(min(car.progress.lap + 1, laps))/\(laps)", bundle: .module)
                            .font(Retro.font(15, weight: .regular))
                    }
                    speedLine(car: car)
                }
            } else {
                // Time trial: the running clock over the laps already driven.
                timeTrialLines(car: car)
            }
        }
    }

    /// **How fast you are going, in km/h.**
    ///
    /// The sim thinks in units per second, which means nothing to a player and
    /// makes "is this fast?" unanswerable — `WorldScale` is the one place that
    /// decides how a unit reads (chosen so the numbers sound fast, since the
    /// world has no true scale to be accurate about).
    ///
    /// Smaller and dimmer than the lap line: a speedometer is glanced at, not
    /// read, and the lap counter is what a player is actually racing against.
    private func speedLine(car: Car) -> some View {
        Text(verbatim: WorldScale.speedLabel(unitsPerSecond: car.state.velocity.length))
            .font(Retro.font(11, weight: .regular).monospacedDigit())
            .opacity(0.75)
    }

    /// The finish state, centered in the band: a bold final position, then the
    /// lap splits and a summed total in one aligned "label … time" column —
    /// an unmistakable "you're done, here's how it went". Kept narrow so it
    /// fits a quarter-screen band on the smallest phones.
    @ViewBuilder private func finishCard(car: Car, index: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(index < colors.count ? colors[index] : .white)
                    .frame(width: 16, height: 16)
                if let place = shownPlace[index] {
                    Text(verbatim: ordinal(place))
                        .font(Retro.font(30, weight: .black))
                        .monospacedDigit()
                }
            }
            splitColumn(car: car)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Retro.ground.opacity(0.82))
        .overlay(RetroBevel(thickness: 2))
    }

    /// One aligned column: a "★ Lap N … time" row per lap (the best lap gets
    /// the star, in a fixed slot so all rows line up), a divider, then a
    /// "Total … time" row so the total reads as the sum. Times right-align,
    /// never wrap, and all share one weight; the whole column stays narrow.
    @ViewBuilder private func splitColumn(car: Car) -> some View {
        VStack(spacing: 3) {
            ForEach(Array(car.progress.lapTimes.enumerated()), id: \.offset) { lap, ticks in
                splitRow(
                    Text("Lap \(lap + 1)", bundle: .module), ticks: ticks,
                    best: ticks == car.progress.bestLapTicks)
            }
            if let finished = car.progress.finishedAt, !car.progress.lapTimes.isEmpty {
                Divider().overlay(.white.opacity(0.3))
                splitRow(
                    Text("Total", bundle: .module),
                    ticks: finished - race.config.countdownTicks, best: false)
            }
        }
        .frame(width: 150)
    }

    /// One "★ label … time" row: a fixed star slot (gold on the best lap,
    /// invisible otherwise, so every row lines up), the label, then the
    /// right-aligned time. Uniform weight; the time never wraps.
    ///
    /// `record` promotes the row to a TRACK record rather than merely this run's best —
    /// the star turns into a crown and the time brightens. A separate glyph rather than a
    /// word: the column is 124pt wide, and "Record" would not fit beside a time.
    private func splitRow(_ label: Text, ticks: Tick, best: Bool, record: Bool = false)
        -> some View
    {
        HStack(spacing: 6) {
            Image(systemName: record ? "crown.fill" : "star.fill")
                .font(.system(size: 8))
                .foregroundStyle(.yellow)
                .opacity(best || record ? 1 : 0)
            // **Never wraps.** The label had no line limit, which was survivable in
            // the old proportional face and is not in a monospaced one — "Lap 2" and
            // "Total" both broke across two lines in a 124pt column. Reported from
            // device. The time already had `fixedSize`; the label needed the same.
            label
                .font(Retro.caption)
                .opacity(0.6)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 6)
            Text(verbatim: formatTicks(ticks))
                .font(Retro.font(13, weight: .regular))
                .opacity(record ? 1 : 0.9)
                .fontWeight(record ? .bold : .regular)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// **A time trial is its history**, not just its best: the running clock, then the
    /// laps already driven so you can see whether you are improving or fading.
    ///
    /// A trial laps forever, so only the most recent `Self.shownLaps` are listed — an
    /// unbounded column would run off a phone. The best lap is pinned below when it has
    /// scrolled out of that window, so the target never disappears.
    ///
    /// **A trial has no ending**, so a record can only be reported while it runs. The mark
    /// is deliberately quiet — the best line it already shows says "Record" — rather than a
    /// banner interrupting a lap that is still being driven.
    @ViewBuilder private func timeTrialLines(car: Car) -> some View {
        let lapTicks = max(
            0, race.tick - max(car.progress.lapStartTick, race.config.countdownTicks))
        let history = LapHistory(lapTimes: car.progress.lapTimes, limit: Self.shownLaps)
        // The run's best IS the track record only when this run set it — the book is
        // written as the lap lands, so it cannot be asked after the fact.
        let setRecord = records.lapRecord != nil
        VStack(alignment: .trailing, spacing: 2) {
            Text(verbatim: formatTicks(lapTicks))
                .font(Retro.font(19))
            ForEach(history.rows, id: \.number) { row in
                splitRow(
                    Text("Lap \(row.number)", bundle: .module), ticks: row.ticks,
                    best: row.isBest, record: row.isBest && setRecord)
            }
            if let best = history.pinnedBest {
                Divider().overlay(.white.opacity(0.3))
                splitRow(
                    Text("Best", bundle: .module), ticks: best, best: true,
                    record: setRecord)
            }
        }
        .frame(width: 150)
    }

    /// How many recent laps the time-trial chip lists.
    private static let shownLaps = 5
}

/// Final standings once every car has taken the flag.
