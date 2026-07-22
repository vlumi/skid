import SkidCore
import SwiftUI

/// The race itself: world canvas, per-player d-pad overlays, zone chrome,
/// HUD, the multitouch input surface, and the results card.
struct RaceScreen: View {
    @ObservedObject var game: CouchGame
    @ObservedObject var session: GameSession
    @ObservedObject var rig: CouchRig

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                TimelineView(.animation) { timeline in
                    // Step the sim on the main actor, then hand the Canvas
                    // plain value copies — its renderer closure is not
                    // MainActor. (`let _ =` is the ViewBuilder side-effect
                    // idiom; a bare `_ =` isn't a valid builder statement.)
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = step(
                        size: geo.size,
                        time: timeline.date.timeIntervalSinceReferenceDate
                    )
                    let race = session.race
                    let colors = game.carColors
                    let scene = WorldScene(
                        race: race, marks: session.marks, gateSpans: session.gateSpans,
                        colors: colors, ghosts: session.ghost?.cars ?? []
                    )
                    let pads = padOverlays()
                    let zones = zoneChrome()
                    ZStack {
                        Canvas { context, size in
                            var world = context
                            TrackRenderer.draw(scene: scene, into: &world, size: size)
                            for zone in zones {
                                TrackRenderer.drawZone(zone, into: &context)
                            }
                            for pad in pads {
                                TrackRenderer.drawDPad(pad, into: &context)
                            }
                        }
                        InputSurface(rig: rig)
                        RaceHUD(race: race, colors: colors)
                        if race.phase == .finished {
                            ResultsCard(game: game, race: race, colors: colors)
                        }
                    }
                }
            }
            .ignoresSafeArea()

            HStack(spacing: 10) {
                Button {
                    rig.cycleScheme()
                } label: {
                    Text(rig.schemeLabel, bundle: .module).pillStyle()
                }
                Button {
                    game.raceAgain()
                } label: {
                    Text("Reset", bundle: .module).pillStyle()
                }
                Button {
                    game.backToSetup()
                } label: {
                    Text("Setup", bundle: .module).pillStyle()
                }
            }
            .padding()
        }
    }

    private func step(size: CGSize, time: TimeInterval) {
        rig.layout(size: CGRect(origin: .zero, size: size).size)
        session.advance(to: time)
        game.noteProgress()
    }

    /// Every active floating d-pad, in its owner's color.
    private func padOverlays() -> [DPadOverlay] {
        guard rig.scheme == .dpad else { return [] }
        return rig.players.compactMap { controls in
            guard let origin = controls.dpad.origin else { return nil }
            return DPadOverlay(
                origin: origin,
                up: controls.dpad.up,
                radius: controls.dpad.radius,
                input: controls.dpad.input(for: controls.player, at: session.race.tick),
                color: CouchGame.palette[controls.colorIndex]
            )
        }
    }

    /// Zone outlines + corner tabs, only when the screen is shared.
    private func zoneChrome() -> [ZoneChrome] {
        guard rig.players.count > 1 else { return [] }
        return rig.players.map { controls in
            ZoneChrome(
                rect: controls.zone,
                up: controls.up,
                color: CouchGame.palette[controls.colorIndex]
            )
        }
    }
}

/// Everything the renderer needs to draw the floating d-pad, colored by the
/// owning player's car color.
struct DPadOverlay {
    var origin: Vec2
    var up: Vec2
    var radius: Double
    var input: CarInput
    var color: Color
}

/// A player's control zone, drawn as faint chrome so everyone knows whose
/// corner is whose.
struct ZoneChrome {
    var rect: CGRect
    var up: Vec2
    var color: Color
}

/// Countdown, per-player lap chips, race clock — minimal, in the classics'
/// spirit.
struct RaceHUD: View {
    let race: Race
    let colors: [Color]

    var body: some View {
        ZStack {
            if case .countdown(let remaining) = race.phase {
                Text(verbatim: "\((remaining + Race.tickRate - 1) / Race.tickRate)")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            } else if race.phase == .running, race.raceTicks < Race.tickRate * 3 / 4 {
                Text("GO!", bundle: .module)
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let laps = race.config.laps {
                    ForEach(Array(race.cars.enumerated()), id: \.offset) { index, car in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(index < colors.count ? colors[index] : .white)
                                .frame(width: 12, height: 12)
                            if let finished = car.progress.finishedAt {
                                Text(
                                    verbatim: formatTicks(finished - race.config.countdownTicks)
                                )
                                .font(.subheadline.monospacedDigit().bold())
                            } else {
                                Text(
                                    "Lap \(min(car.progress.lap + 1, laps))/\(laps)",
                                    bundle: .module
                                )
                                .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                    Text(verbatim: formatTicks(race.raceTicks))
                        .font(.headline.monospacedDigit())
                        .padding(.top, 2)
                } else if let car = race.cars.first {
                    // Time trial: the live lap clock is the whole game.
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
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .padding(.leading, 16)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
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
